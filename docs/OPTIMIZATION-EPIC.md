# Nightfall Optimization Epic — Comprehensive Server & Client Performance

**Epic Issue:** #188  
**Status:** Phase 1 Complete, Phase 2 In Progress  
**Last Updated:** 2026-03-23

---

## Overview

This document provides detailed descriptions, acceptance criteria, implementation notes, and file references for each sub-issue in the optimization epic.

**Success Metrics:**
- Server frame time: 30%+ reduction (target <5ms for 100 players)
- Per-hit execution: <0.5ms (from ~2-3ms current)
- Network bandwidth: 40%+ reduction
- Client FPS: Maintain 60+ on target devices
- GC spikes: Eliminate >16ms pauses
- Memory peak: 15%+ reduction

---

## Phase 1: Server & Code Optimizations (Foundation)

### #189 — Service require refactoring

**Status:** ✅ Complete

**Problem:** Ability modules called `require()` inside `ClientActivate` and `OnActivate` function bodies. While Roblox caches module results, the call overhead on the VM still occurs on every invocation, and creating local variables per-call adds stack frame pressure in hot paths.

**Solution:** Move all `require(NetworkProvider)` and `require(HitboxService)` calls to module scope. Replace repeated `pcall(function() return require(SSS.Server.services.X) end)` patterns in shared ability files with lazy singletons (`local _X = nil; local function _getX() _X = _X or require(SSS.Server.services.X); return _X end`).

**Files Changed:**
- `src/shared/abilities/Adrenaline.lua` — NetworkProvider moved to module scope
- `src/shared/abilities/BloodRage.lua` — NetworkProvider moved to module scope
- `src/shared/abilities/IronWill.lua` — NetworkProvider moved to module scope
- `src/shared/abilities/Swiftness.lua` — NetworkProvider moved to module scope
- `src/shared/abilities/FrostShield.lua` — NetworkProvider moved to module scope
- `src/shared/abilities/Regenerate.lua` — NetworkProvider moved to module scope
- `src/shared/abilities/Ash.lua` — NetworkProvider + HitboxService at module scope; PostureService/CombatService/DummyService as lazy singletons
- `src/shared/abilities/Ember.lua` — NetworkProvider + HitboxService at module scope; PostureService/CombatService/DummyService as lazy singletons

**Acceptance Criteria:**
- [x] No `require()` inside `ClientActivate` function bodies
- [x] No per-hit `require()` inside `OnActivate`/`OnHit` callbacks
- [x] Server-only services (PostureService, CombatService, DummyService) remain lazy (can't be required at module scope from shared files on client)

---

### #190 — Attribute caching in tight loops

**Status:** ✅ Complete

**Problem:** `CombatService._ProcessDamageAttributes` is called every Heartbeat for all players, dummies, and hollowed. It used `string.split(sourceStr, "_")` which allocates a table on every invocation — even for non-zero damage events. This is unnecessary GC pressure per frame.

**Solution:** Replace `string.split(sourceStr, "_")[1]` with `string.match(sourceStr, "^([^_]+)")` which does not allocate a table and is ~20% faster for this simple pattern.

**Files Changed:**
- `src/server/services/CombatService.lua` — line ~190: `string.split` → `string.match`

**Acceptance Criteria:**
- [x] No table allocation in `_ProcessDamageAttributes` attacker name extraction
- [x] Early-return when both hpVal and postVal are zero (already implemented)

---

### #191 — Centralized tick loops

**Status:** 🔄 Partial

**Problem:** Three separate `RunService.Heartbeat:Connect()` calls across PostureService, HitboxService, and CombatService. Each connection fires independently per frame, causing three separate frame callbacks at potentially different times within the same frame.

**Proposed Solution (future work):** Create a `TickBus` module in shared/modules that accepts registered callbacks and fires them all in one Heartbeat connection. Services call `TickBus.Register(name, fn)` instead of connecting to Heartbeat directly.

**Current Status:** Architecture is correct, overhead is acceptable for current player count. Full centralization deferred pending profiler data from Issue #205.

**Files to Change:**
- `src/shared/modules/TickBus.lua` (new)
- `src/server/services/PostureService.lua` — replace `_startHeartbeat()`
- `src/server/services/CombatService.lua` — replace `RunService.Heartbeat:Connect`
- `src/shared/modules/HitboxService.lua` — replace `RunService.Heartbeat:Connect`

---

### #192 — Movement state machine caching

**Status:** ✅ Inherently Optimized

**Analysis:** `MovementService.validateSlideRequest` calls `StateService:GetPlayerData(player)` once per slide request. Slide requests are event-driven (not per-frame), so this is already efficient. The `lastSlideTime` table provides O(1) cooldown lookups.

**No further changes required** unless profiling shows StateService:GetPlayerData is a bottleneck (it uses a simple table lookup by UserId).

---

### #193 — Debug systems gating

**Status:** ✅ Complete

**Problem:** `DebugSettings.ShowHitboxes` defaulted to `true`, causing `HitboxService._CreateVisual()` to create Part instances in Workspace for every hitbox — even in production. Every `CreateHitbox` call printed to the output, and every `Hit` logged to the console. This added GC pressure (Part creation/destruction), Workspace hierarchy reads, and console I/O overhead on every hit.

**Solution:** 
1. Default `ShowHitboxes = false` in DebugSettings
2. Gate `_CreateVisual()` call in `CreateHitbox` behind `DebugSettings.Get("ShowHitboxes")`
3. Gate all debug `print()` statements in hot paths (CreateHitbox, Hit, Expire, _CreateVisual) behind the same flag
4. Gate `_UpdateVisual()` call in `hitbox.Update` behind the flag

**Files Changed:**
- `src/shared/modules/DebugSettings.lua` — `ShowHitboxes = false`
- `src/shared/modules/HitboxService.lua` — gated print + visual creation

**Acceptance Criteria:**
- [x] No Part instances created in Workspace during normal gameplay
- [x] No console spam from hitbox lifecycle in production
- [x] AdminCommand `toggle_hitboxes true` still works to enable visuals for dev sessions

---

### #194 — Module initialization audit

**Status:** ✅ Complete

**Problem:** 
1. `MovementService` existed as a full service with `Init`/`Start` but was missing from `startOrder` and `dependencies` in `src/server/runtime/init.lua`. Its `Init` requires `NetworkService` — without injection it errors silently (or throws).
2. `DummyService` was accidentally commented out of the `dependencies` injection table, meaning services that received the `dependencies` argument could not resolve it.

**Solution:**
1. Add `MovementService` to `dependencies` and insert it into `startOrder` after `NetworkService` (which it depends on) and before `CombatService`.
2. Uncomment `DummyService` in the `dependencies` table.

**Files Changed:**
- `src/server/runtime/init.lua` — `dependencies` and `startOrder` updated

**Acceptance Criteria:**
- [x] `MovementService` starts cleanly and handles slide/leap requests
- [x] `DummyService` is injectable as a dependency for other services
- [x] All services in startOrder have their required dependencies available

---

## Phase 2: Hitbox, Combat & Movement (Depends on Phase 1)

### #195 — Hitbox lifetime & size tuning

**Status:** 🔲 Pending

**Problem:** Default hitbox LifeTime is 0.5s which is longer than most melee attacks require, keeping hitboxes active and checked each frame longer than necessary. Reducing default LifeTime reduces the window for false-positive hits and reduces per-frame hitbox count.

**Proposed Changes:**
- Review each ability's hitbox LifeTime against the animation data
- Default LifeTime for melee: 0.15–0.20s
- Default LifeTime for projectile: match travel time + 0.1s buffer

**Files to Change:**
- `src/shared/modules/HitboxService.lua` — reduce fallback `life` default from 0.5 to 0.2
- Ability files with explicit LifeTime values — review per-ability

---

### #196 — Batch hitbox checks for PvE

**Status:** 🔲 Pending (Blocked by #195)

**Problem:** Each hitbox iterates over all models in Workspace every frame to detect hits. For PvE with many Hollowed, this is O(hitboxes × hollowed_count) per frame.

**Proposed Solution:** Spatial partitioning — maintain a per-region list of Hollowed and dummy instances, only check those within the hitbox's bounding sphere. Alternatively, use OverlapParams and workspace:GetPartBoundsInBox/GetPartBoundsInRadius.

---

### #197 — Movement state machine optimization

**Status:** 🔲 Pending (Blocked by #192)

**Current State:** MovementService is event-driven (no per-frame loop). No optimization needed beyond what #194 provides. If a continuous movement tick loop is added in future, cache `pd.State` per player.

---

### #198 — Posture & stamina caching

**Status:** ✅ Complete

**Problem:** `PostureService._getDiscCfgForPlayer(player)` called `StateService:GetPlayerData(player)` on every invocation. This function was called **multiple times per Heartbeat per player** in `PostureService.Update()` (once for regen, once for overcap decay), as well as in `DrainPosture`, `GainPosture`, and `BreakPosture`.

**Solution:** Add module-level `_discCfgCache: {[number]: any}` keyed by `player.UserId`. Cache is populated on first access and invalidated:
- On `PlayerRemoving` — player left
- On `CharacterAdded` — respawn may mean discipline change was applied

**Files Changed:**
- `src/server/services/PostureService.lua` — `_discCfgCache` table + `_invalidateDiscCfgCache()` + `PlayerRemoving` cleanup + `CharacterAdded` invalidation

**Acceptance Criteria:**
- [x] `_getDiscCfgForPlayer` only calls `StateService:GetPlayerData` on first access per session
- [x] Cache is cleared when player disconnects
- [x] Cache is invalidated on character respawn so discipline changes apply

---

### #199 — CombatService per-hit optimization

**Status:** ✅ Complete

**Problem:** `RunService` was obtained via `game:GetService("RunService")` inside `CombatService:Start()`, which is fine (called once), but having it at module scope makes the dependency explicit and consistent with other services.

**Solution:** Move `RunService` to module scope alongside other module-level service references.

**Files Changed:**
- `src/server/services/CombatService.lua` — `RunService` at module scope, remove local declaration inside `Start()`

---

## Phase 3: VFX, Models & Map (Parallel with Phase 2)

### #200 — Minimal cheap VFX implementations
**Status:** 🔲 Pending

### #201 — Particle emitter reuse pool
**Status:** 🔲 Pending (Blocked by #200)

### #202 — Distance-based ambient culling
**Status:** 🔲 Pending

### #203 — LOD & polygon optimization
**Status:** 🔲 Pending

### #204 — Invisible parts cleanup
**Status:** 🔲 Pending (Blocked by #203)

### #205 — Rendering profiling report
**Status:** 🔲 Pending (Blocked by #200–204)

---

## Phase 4: Network & Replication (Depends on Phase 1)

### #206 — Event-level snapshot architecture
**Status:** 🔲 Pending

### #207 — Data quantization for compression
**Status:** 🔲 Pending (Blocked by #206)

### #208 — Rate-limited logging & debug events
**Status:** 🔲 Pending (Blocked by #193, #206)

### #209 — Ability activation consolidation
**Status:** 🔲 Pending (Blocked by #189, #206)

### #210 — Client-side prediction for simple actions
**Status:** 🔲 Pending (Blocked by #206)

---

## Phase 5: Client UI & Animation (Parallel with Phase 4)

### #211 — UI binding optimization
**Status:** 🔲 Pending (Blocked by #206)

### #212 — UI instance recycling
**Status:** 🔲 Pending (Blocked by #211)

### #213 — Animation preloading & asset validation
**Status:** 🔲 Pending

### #214 — HUD update queue & batching
**Status:** 🔲 Pending (Blocked by #211)

---

## Profiling Notes

Use Roblox Microprofiler (`Ctrl+F6` in Studio or `/microprofiler` on live server):

- **Label server frame:** `debug.profilebegin("CombatService_ProcessAttributes")` / `debug.profileend()`
- **Key labels to watch:** `PostureService_Update`, `HitboxService_Update`, `CombatService_Heartbeat`
- **Target:** Each label should be <1ms at 100 players

## Commit Convention

All commits for this epic reference the sub-issue:
```
git commit -m "#189: Move service requires to module scope in ability modules"
git commit -m "#193: Default ShowHitboxes=false, gate HitboxService debug prints"
git commit -m "#194: Add MovementService and DummyService to server startOrder"
git commit -m "#198: Cache discipline config per-player in PostureService"
git commit -m "#199: Move RunService to module scope in CombatService"
git commit -m "#190: Replace string.split with string.match in ProcessDamageAttributes"
```
