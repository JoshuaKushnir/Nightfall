# Optimization Epic: Comprehensive Server & Client Performance

**Epic ID:** TBD (to be created)
**Priority:** High
**Status:** Planning
**Target Duration:** 8-12 weeks
**Phases:** 5
**Sub-Issues:** 26

---

## Overview

This epic consolidates all performance optimization work across Nightfall's codebase. The goal is to reduce per-frame overhead, minimize network traffic, and maximize client efficiency—all without changing gameplay behavior.

## Success Metrics

| Metric | Target | Baseline (Current) |
|--------|--------|-------------------|
| Server frame time | <5ms for 100 players | ~15-20ms |
| Per-hit execution | <0.5ms | ~2-3ms |
| Network bandwidth | 40%+ reduction | Unmetered |
| Client FPS | 60+ on target devices | Variable |
| GC spike elimination | No >16ms pauses | Frequent spikes |
| Memory peak reduction | 15%+ | Unmetered |

---

## Phase 1: Server & Code Optimizations (Foundation)

**Duration:** Weeks 1-2
**Priority:** Critical (blocks Phases 2 & 4)
**Issues:** #189-#194

These foundational optimizations must complete before Phase 2 (Combat) and Phase 4 (Network) can begin.

### Issue #189: Service Require Refactoring

**Priority:** High
**Labels:** `phase-1`, `backend`, `tech-debt`, `high`

**Overview:**
Move all service requires from per-call/per-hit scope to module scope. Current pattern uses `pcall(require(...))` inside hot loops, causing thousands of redundant dictionary lookups per second.

**Acceptance Criteria:**
- [ ] All ability modules move CombatService, DummyService, HitboxService requires to top of file
- [ ] Remove all `pcall(require(...))` patterns from OnHit callbacks
- [ ] Remove all `require()` calls from inside functions that execute >10x/sec
- [ ] Profile before/after: measure combat loop frame time reduction (target: 10-15% improvement)
- [ ] Zero type errors with `--!strict`

**Files Affected:**
- `src/shared/abilities/*.lua` (13 files: Ember, Ash, Tide, Void, Gale, etc.)
- `src/server/services/CombatService.lua` (remove lazy requires if safe)
- `src/server/services/AbilitySystem.lua`

**Implementation Tasks:**
1. Audit all 13 ability modules for require patterns
2. Move service requires to module scope (top of file after type imports)
3. Replace `local success, service = pcall(require, path)` with direct `require(path)`
4. Run profiler: capture baseline combat frame time
5. Apply changes, re-profile, document improvement

**Notes:**
- Lazy-requires were originally added to break circular dependencies
- Verify no circular deps remain before moving to module scope
- If circular dep found: use Init() phase dependency injection instead

---

### Issue #190: Attribute Caching in Tight Loops

**Priority:** High
**Labels:** `phase-1`, `backend`, `performance`, `high`

**Overview:**
Replace repeated `GetAttribute()` calls in per-frame loops with cached values. Current pattern queries Roblox Instance attributes 100+ times per frame in CombatService damage processing.

**Acceptance Criteria:**
- [ ] CombatService: Cache weapon damage attributes at equip time, invalidate on unequip
- [ ] PostureService: Cache max posture values per player, refresh on stat changes only
- [ ] MovementService: Cache speed modifiers, refresh on state transitions only
- [ ] Profile before/after: measure attribute read overhead reduction (target: 20%+ improvement in affected loops)
- [ ] No stale data: cache invalidation triggers documented

**Files Affected:**
- `src/server/services/CombatService.lua` (lines 144-165: damage processing loop)
- `src/server/services/PostureService.lua`
- `src/server/services/MovementService.lua`
- Add `_attributeCache` tables to affected services

**Implementation Tasks:**
1. Identify all GetAttribute() calls in Heartbeat/RunService loops
2. Add cache tables to service modules (e.g., `_weaponDamageCache[player]`)
3. Implement cache population at equip/load time
4. Implement cache invalidation on unequip/stat change events
5. Replace GetAttribute() with cache lookups in hot paths
6. Profile before/after

**Notes:**
- Cache must invalidate on weapon swap, stat changes, respawn
- Consider TTL-based cache refresh for paranoia (e.g., refresh every 5s as safety net)

---

### Issue #191: Centralized Tick Loops

**Priority:** Medium
**Labels:** `phase-1`, `infrastructure`, `refactor`, `medium`

**Overview:**
Consolidate multiple Heartbeat connections into a single centralized tick dispatcher. Current architecture has 8+ separate Heartbeat connections across services, causing fragmentation and preventing unified profiling.

**Acceptance Criteria:**
- [ ] Create `TickManager` module with single Heartbeat connection
- [ ] Register services with priority levels (PrePhysics, Physics, PostPhysics, UI)
- [ ] Migrate all services to use TickManager instead of direct Heartbeat
- [ ] Profile: measure tick loop overhead reduction (target: 5-10% improvement)
- [ ] Add per-service tick budget tracking for future monitoring

**Files Affected:**
- `src/shared/modules/TickManager.lua` (create new)
- `src/server/services/CombatService.lua` (migrate Heartbeat connection)
- `src/server/services/HollowedService.lua` (migrate tick loop)
- `src/shared/modules/HitboxService.lua` (migrate TestHitbox loop)
- `src/server/services/PostureService.lua`
- All other services with Heartbeat connections

**Implementation Tasks:**
1. Create TickManager with priority-based registration
2. Implement tick budget tracking (for future monitoring)
3. Migrate CombatService damage processing loop
4. Migrate HitboxService TestHitbox loop
5. Migrate HollowedService AI tick loop
6. Migrate remaining services
7. Profile unified tick performance

**Notes:**
- Priority levels ensure execution order (e.g., Physics before AI)
- Future enhancement: tick budget warnings for services exceeding thresholds

---

### Issue #192: Movement State Machine Caching

**Priority:** Medium
**Labels:** `phase-1`, `backend`, `performance`, `medium`

**Overview:**
Cache movement state transition validation results to avoid redundant state machine lookups. Current pattern re-validates same transitions repeatedly during multi-frame actions (e.g., attacking, casting).

**Acceptance Criteria:**
- [ ] StateService: Add transition result cache (from_state, to_state) → boolean
- [ ] Cache populated during first transition validation
- [ ] Cache invalidated on state change or new state added to system
- [ ] Profile: measure state validation overhead reduction (target: 30%+ improvement in state validation calls)
- [ ] No false positives: cache must respect dynamic state rules

**Files Affected:**
- `src/shared/modules/StateService.lua` (add cache to CanTransition function)
- Document cache invalidation strategy in module header

**Implementation Tasks:**
1. Add `_transitionCache` table to StateService
2. Implement cache key generation: `fromState .. "_to_" .. toState`
3. Wrap CanTransition() with cache check
4. Add cache invalidation on state registration
5. Profile before/after state transition overhead

**Notes:**
- Cache must be per-server (not per-player) since state rules are global
- Consider pre-populating cache at startup with all valid transitions

---

### Issue #193: Debug Systems Gating

**Priority:** Low
**Labels:** `phase-1`, `infrastructure`, `tech-debt`, `low`

**Overview:**
Gate all debug visualization and logging behind runtime flags. Current pattern creates debug parts and prints warnings even when debug mode is disabled, wasting memory and cycles.

**Acceptance Criteria:**
- [ ] DebugSettings module: Add runtime toggle system (not compile-time)
- [ ] HitboxService: Gate visualization part creation behind DebugSettings.ShowHitboxes
- [ ] All services: Gate verbose logging behind DebugSettings.VerboseLogging
- [ ] Profile: measure overhead reduction when debug disabled (target: 5%+ improvement)
- [ ] Admin command to toggle debug flags at runtime

**Files Affected:**
- `src/shared/modules/DebugSettings.lua` (extend with runtime flags)
- `src/shared/modules/HitboxService.lua` (gate visualization)
- `src/server/services/CombatService.lua` (gate verbose logging)
- `src/server/services/NetworkService.lua` (gate rate limit warnings)
- All services with debug logging

**Implementation Tasks:**
1. Add runtime flag system to DebugSettings (table of boolean flags)
2. Add admin command to toggle flags via RemoteEvent
3. Gate HitboxService part creation: `if DebugSettings.ShowHitboxes then`
4. Gate verbose warn() calls in all services
5. Profile memory usage with debug disabled

**Notes:**
- Flags must be runtime-togglable for playtesting without rejoining
- Default to disabled in production, enabled in Studio

---

### Issue #194: Module Initialization Audit

**Priority:** Low
**Labels:** `phase-1`, `infrastructure`, `audit`, `low`

**Overview:**
Audit all module requires for expensive initialization work at require-time. Move heavy computation to Init() or Start() phases to reduce server startup lag.

**Acceptance Criteria:**
- [ ] Document all modules performing work at require-time (e.g., AnimationLoader building flat DB)
- [ ] Identify modules with >10ms initialization cost
- [ ] Move expensive work to Init() or lazy-initialization pattern
- [ ] Profile: measure server startup time reduction (target: 15%+ faster startup)
- [ ] Document initialization order dependencies

**Files Affected:**
- `src/shared/modules/AnimationLoader.lua` (flat DB build at require)
- `src/shared/modules/AspectRegistry.lua`
- `src/shared/modules/AbilityRegistry.lua`
- `src/shared/modules/WeaponRegistry.lua`
- All registries and loaders

**Implementation Tasks:**
1. Profile each module require time (use `tick()` wrapper)
2. Document modules with >10ms cost
3. Refactor expensive work to Init() or lazy pattern
4. Re-profile startup time

**Notes:**
- AnimationLoader's flat DB is valuable cache—consider keeping but moving to async Init()
- Balance between startup cost and runtime performance

---

## Phase 2: Hitbox, Combat & Movement (Depends on Phase 1)

**Duration:** Weeks 3-4
**Priority:** High
**Dependencies:** Must complete Phase 1 before starting
**Issues:** #195-#199

### Issue #195: Hitbox Lifetime & Size Tuning

**Priority:** High
**Labels:** `phase-2`, `combat`, `performance`, `high`
**Depends On:** #189, #191

**Overview:**
Reduce hitbox active lifespans and physical sizes to minimum viable values. Current pattern uses conservative 0.5s lifespans and oversized shapes, causing unnecessary collision tests.

**Acceptance Criteria:**
- [ ] Audit all abilities for hitbox parameters (lifetime, size)
- [ ] Reduce lifetimes to match actual attack active frames (target: 0.15-0.3s for most attacks)
- [ ] Shrink hitbox dimensions to tight bounds around weapons
- [ ] Profile: measure collision test count reduction (target: 40%+ fewer tests per frame)
- [ ] Gameplay validation: no phantom hits, no missed hits that should land

**Files Affected:**
- `src/shared/abilities/*.lua` (all 13 ability modules)
- `src/shared/modules/HitboxService.lua` (adjust default lifetime constant)
- Document recommended lifetimes per attack speed tier

**Implementation Tasks:**
1. Profile current collision test count per frame
2. Audit all CreateHitbox() calls for lifetime and size params
3. Reduce lifetimes: fast attacks 0.15s, slow attacks 0.3s
4. Shrink sizes: use weapon bounds instead of padded spheres
5. Playtest for false negatives (missed hits)
6. Re-profile collision test count

**Notes:**
- Balance between performance and gameplay feel
- Fast weapons (daggers) can use shorter lifetimes than slow weapons (greatswords)

---

### Issue #196: Batch Hitbox Checks for PvE

**Priority:** Medium
**Labels:** `phase-2`, `combat`, `performance`, `medium`
**Depends On:** #189, #195

**Overview:**
Batch collision checks for multiple hitboxes against shared target sets. Current pattern tests each hitbox independently against full world query, duplicating work when multiple hitboxes active.

**Acceptance Criteria:**
- [ ] HitboxService: Group active hitboxes by owner and shape type
- [ ] Perform single spatial query per group, share results across hitboxes
- [ ] Profile: measure spatial query count reduction (target: 30%+ fewer queries)
- [ ] No false positives or negatives in hit detection

**Files Affected:**
- `src/shared/modules/HitboxService.lua` (refactor TestHitbox loop to batch queries)

**Implementation Tasks:**
1. Profile current spatial query count (GetPartBoundsInRadius calls)
2. Refactor TestHitbox to group hitboxes by owner
3. Perform single query per owner, filter results per hitbox
4. Re-profile query count
5. Playtest for correctness

**Notes:**
- Only batch hitboxes with similar shapes (spheres with spheres, boxes with boxes)
- Use largest dimensions for shared query, filter per-hitbox

---

### Issue #197: Movement State Machine Optimization

**Priority:** Medium
**Labels:** `phase-2`, `backend`, `performance`, `medium`
**Depends On:** #192

**Overview:**
Optimize MovementController state transitions to reduce redundant state checks. Current pattern re-validates state every frame even when no input changes.

**Acceptance Criteria:**
- [ ] Cache last input state (W/A/S/D/Space/Shift/C pressed)
- [ ] Skip state validation when input unchanged
- [ ] Profile: measure state validation call reduction (target: 50%+ fewer validations)
- [ ] No input lag or dropped transitions

**Files Affected:**
- `src/client/controllers/MovementController.lua`

**Implementation Tasks:**
1. Add `_lastInputState` table to controller
2. Compare current input to cached input before calling state machine
3. Profile state validation call frequency
4. Playtest for input responsiveness

**Notes:**
- Must still validate on server state changes (e.g., stunned, ragdolled)

---

### Issue #198: Posture & Stamina Caching

**Priority:** Medium
**Labels:** `phase-2`, `backend`, `performance`, `medium`
**Depends On:** #190, #192

**Overview:**
Cache posture and stamina max values per player, refresh only on stat changes. Current pattern recalculates from base stats + discipline modifiers every frame.

**Acceptance Criteria:**
- [ ] PostureService: Add max posture cache per player
- [ ] Refresh cache only on discipline stat changes or equipment changes
- [ ] Profile: measure posture calculation overhead reduction (target: 90%+ elimination of redundant calcs)
- [ ] Correct posture values in all edge cases (respawn, level up, etc.)

**Files Affected:**
- `src/server/services/PostureService.lua`

**Implementation Tasks:**
1. Profile posture calculation frequency
2. Add `_maxPostureCache[player]` table
3. Populate cache on player load, refresh on stat change
4. Replace recalculation with cache lookup
5. Re-profile

**Notes:**
- Cache must invalidate on: level up, equipment change, discipline stat investment

---

### Issue #199: CombatService Per-Hit Optimization

**Priority:** High
**Labels:** `phase-2`, `combat`, `performance`, `high`
**Depends On:** #189, #190

**Overview:**
Optimize damage application hot path to reduce per-hit execution time. Current pattern performs redundant validation checks and attribute lookups.

**Acceptance Criteria:**
- [ ] Cache weapon damage at equip time (leverage #190 work)
- [ ] Pre-validate hit eligibility before damage calculation
- [ ] Reduce damage variance calculation to single random call
- [ ] Profile: measure per-hit execution time (target: <0.5ms from ~2-3ms)
- [ ] Maintain all gameplay behavior (crits, variance, multipliers)

**Files Affected:**
- `src/server/services/CombatService.lua` (ValidateHit and damage application functions)

**Implementation Tasks:**
1. Profile per-hit execution time (instrument ValidateHit)
2. Cache weapon damage on equip (leverage #190)
3. Add early-exit checks before damage calc
4. Optimize damage variance to single Random.new():NextNumber() call
5. Re-profile per-hit time

**Notes:**
- Maintain damage variance (±10%), crit chance (15%), multipliers (DamageBoost, Weakened)

---

## Phase 3: VFX, Models & Map (Parallel with Phase 2)

**Duration:** Weeks 3-4
**Priority:** Medium
**Dependencies:** None (can start immediately)
**Issues:** #200-#205

### Issue #200: Minimal Cheap VFX Implementations

**Priority:** Medium
**Labels:** `phase-3`, `frontend`, `performance`, `medium`

**Overview:**
Replace VFX stubs with minimal performant implementations using cheap effects (Part color changes, simple ParticleEmitters).

**Acceptance Criteria:**
- [ ] Identify all VFX stub functions in abilities
- [ ] Implement minimal VFX: color flash, small particle burst, brief transparency change
- [ ] Profile: measure VFX overhead (target: <0.1ms per effect)
- [ ] Visual quality check: effects visible but not distracting

**Files Affected:**
- `src/shared/abilities/*.lua` (all ability VFX_Function stubs)

**Implementation Tasks:**
1. Audit all VFX stub functions
2. Implement minimal effects (Part.Color tween, simple ParticleEmitter)
3. Profile VFX overhead
4. Visual QA in Studio

**Notes:**
- Use TweenService for smooth color transitions
- ParticleEmitters should emit 5-10 particles max
- Avoid nested transparency changes (causes re-renders)

---

### Issue #201: Particle Emitter Reuse Pool

**Priority:** Medium
**Labels:** `phase-3`, `frontend`, `performance`, `medium`
**Depends On:** #200

**Overview:**
Create object pool for ParticleEmitters to avoid frequent Instance.new() calls. Current pattern creates new emitters per effect, causing GC pressure.

**Acceptance Criteria:**
- [ ] Create ParticleEmitterPool module with Get() and Return() methods
- [ ] Pool sized for peak usage (e.g., 50 emitters)
- [ ] Profile: measure GC pause reduction (target: eliminate >5ms pauses)
- [ ] No visual artifacts from emitter reuse

**Files Affected:**
- `src/client/modules/ParticleEmitterPool.lua` (create new)
- `src/shared/abilities/*.lua` (use pool instead of Instance.new)

**Implementation Tasks:**
1. Profile current GC pauses during heavy VFX usage
2. Create ParticleEmitterPool with pre-allocated emitters
3. Implement Get() and Return() with property reset
4. Replace Instance.new() calls with pool.Get()
5. Re-profile GC pauses

**Notes:**
- Pool should pre-allocate on Init(), not lazily
- Return() must reset all properties (Transparency, Color, Rate, etc.)

---

### Issue #202: Distance-Based Ambient Culling

**Priority:** Low
**Labels:** `phase-3`, `frontend`, `performance`, `low`

**Overview:**
Cull ambient effects (wind particles, ambient sounds) beyond render distance. Current pattern runs all ambient effects regardless of player proximity.

**Acceptance Criteria:**
- [ ] Implement distance-based culling for ambient ParticleEmitters
- [ ] Cull ambient sounds beyond audio range (50 studs)
- [ ] Profile: measure client frame time improvement (target: 5-10% in dense areas)
- [ ] No pop-in artifacts

**Files Affected:**
- Zone ambient scripts (if any)
- Client ambient controller (if exists)

**Implementation Tasks:**
1. Identify all ambient effects in world
2. Implement distance check loop (every 1s, not per-frame)
3. Enable/disable effects based on distance threshold
4. Profile client frame time in dense zones

**Notes:**
- Update frequency: 1Hz (every second) is sufficient for culling checks
- Use magnitude squared for distance checks (faster than magnitude)

---

### Issue #203: LOD & Polygon Optimization

**Priority:** Medium
**Labels:** `phase-3`, `frontend`, `performance`, `medium`

**Overview:**
Audit world models for polygon count and apply LOD (Level of Detail) systems. Current pattern uses high-poly models at all distances.

**Acceptance Criteria:**
- [ ] Audit world models for polygon count (target: <10k polys per model)
- [ ] Apply Roblox RenderFidelity.Automatic to high-poly models
- [ ] Identify models for manual LOD replacement at distance
- [ ] Profile: measure rendering frame time improvement (target: 10%+ in dense areas)
- [ ] Document high-poly models for artist optimization

**Files Affected:**
- World models in Workspace (manual audit)
- Document findings in `docs/RENDERING_AUDIT.md`

**Implementation Tasks:**
1. Use Studio Model Statistics tool to audit poly counts
2. Apply RenderFidelity.Automatic to models >5k polys
3. Identify models for manual LOD (if any)
4. Profile rendering frame time
5. Document findings

**Notes:**
- RenderFidelity.Automatic is Roblox's built-in LOD system
- Manual LOD only if Automatic insufficient

---

### Issue #204: Invisible Parts Cleanup

**Priority:** Low
**Labels:** `phase-3`, `frontend`, `performance`, `low`
**Depends On:** #203

**Overview:**
Remove or optimize invisible parts used for collision/triggers. Current pattern may have redundant invisible parts causing unnecessary collision checks.

**Acceptance Criteria:**
- [ ] Audit Workspace for Transparency=1 parts
- [ ] Remove parts not used for collision or triggers
- [ ] Set CanCollide=false on decorative invisible parts
- [ ] Profile: measure collision check reduction (target: 5%+ fewer checks)

**Files Affected:**
- World models in Workspace (manual audit)

**Implementation Tasks:**
1. Search Workspace for Transparency=1 parts
2. Validate each part's purpose (collision, trigger, deprecated)
3. Remove deprecated parts
4. Set CanCollide=false on non-functional parts
5. Profile collision check count

**Notes:**
- Keep parts used for zone triggers, collision boundaries
- Remove parts from old systems (e.g., deprecated spawn zones)

---

### Issue #205: Rendering Profiling Report

**Priority:** Low
**Labels:** `phase-3`, `frontend`, `documentation`, `low`
**Depends On:** #200, #201, #202, #203, #204

**Overview:**
Comprehensive rendering profiling report documenting Phase 3 improvements. Capture before/after metrics for all visual optimizations.

**Acceptance Criteria:**
- [ ] Profile rendering frame time before Phase 3 starts
- [ ] Profile after each Phase 3 sub-issue completes
- [ ] Document improvements in `docs/RENDERING_OPTIMIZATION_REPORT.md`
- [ ] Include screenshots of profiler results
- [ ] Recommendations for future rendering work

**Files Affected:**
- `docs/RENDERING_OPTIMIZATION_REPORT.md` (create new)

**Implementation Tasks:**
1. Capture baseline rendering metrics (Studio Microprofiler)
2. Capture metrics after each sub-issue
3. Document improvements in report
4. Add recommendations for Phase 5 polish work

**Notes:**
- Use Studio Microprofiler for rendering frame time
- Test on low-end device settings (Graphics Quality 1-3)

---

## Phase 4: Network & Replication (Depends on Phase 1)

**Duration:** Weeks 5-6
**Priority:** High
**Dependencies:** Must complete Phase 1 before starting
**Issues:** #206-#210

### Issue #206: Event-Level Snapshot Architecture

**Priority:** High
**Labels:** `phase-4`, `networking`, `infrastructure`, `high`
**Depends On:** #189

**Overview:**
Design and implement snapshot-based state sync instead of per-attribute replication. Current pattern sends individual attribute changes, causing network spam.

**Acceptance Criteria:**
- [ ] Design snapshot packet format (position, state, health, posture in single packet)
- [ ] Implement snapshot builder in StateSyncService
- [ ] Replace per-attribute syncs with snapshot broadcasts
- [ ] Profile: measure network bandwidth reduction (target: 40%+ reduction)
- [ ] No desync or stale data

**Files Affected:**
- `src/server/services/StateSyncService.lua`
- `src/shared/types/NetworkTypes.lua` (add Snapshot packet type)

**Implementation Tasks:**
1. Profile current network traffic (use Studio Network Profiler)
2. Design Snapshot packet type (all frequently-changed state in one packet)
3. Implement snapshot builder in StateSyncService
4. Replace individual StateChanged events with single SnapshotUpdate event
5. Re-profile network traffic

**Notes:**
- Snapshot should include: Position, State, Health, Posture, Stamina
- Send snapshots at fixed rate (e.g., 20 Hz) instead of on-change

---

### Issue #207: Data Quantization for Compression

**Priority:** Medium
**Labels:** `phase-4`, `networking`, `performance`, `medium`
**Depends On:** #206

**Overview:**
Quantize continuous values (position, health, posture) to reduce packet size. Current pattern sends full float precision, wasting bandwidth.

**Acceptance Criteria:**
- [ ] Quantize position to nearest 0.1 stud (not full float)
- [ ] Quantize health/posture to integers (not floats)
- [ ] Profile: measure packet size reduction (target: 20%+ smaller packets)
- [ ] No visible jitter or precision loss

**Files Affected:**
- `src/server/services/StateSyncService.lua` (quantize before send)
- `src/client/controllers/StateSyncController.lua` (dequantize on receive)

**Implementation Tasks:**
1. Profile current packet sizes (bytes per snapshot)
2. Implement quantization functions (math.floor(pos * 10) / 10)
3. Apply to position, health, posture
4. Re-profile packet sizes
5. Playtest for precision loss

**Notes:**
- Position: 0.1 stud precision is invisible to player
- Health/Posture: integer precision is sufficient (no fractional health)

---

### Issue #208: Rate-Limited Logging & Debug Events

**Priority:** Low
**Labels:** `phase-4`, `networking`, `performance`, `low`
**Depends On:** #193, #206

**Overview:**
Rate-limit debug logging and non-critical events to reduce network spam. Current pattern may spam warnings in high-activity scenarios.

**Acceptance Criteria:**
- [ ] NetworkService: Add rate limiting for debug events (max 1/sec per event type)
- [ ] CombatService: Rate-limit hit validation warnings
- [ ] Profile: measure network event count reduction (target: 50%+ fewer debug events)
- [ ] Preserve critical error logging (no rate limit on errors)

**Files Affected:**
- `src/server/services/NetworkService.lua` (add debug event rate limiter)
- `src/server/services/CombatService.lua` (rate-limit warnings)

**Implementation Tasks:**
1. Profile network event count (all RemoteEvents)
2. Identify debug/warning events (non-critical)
3. Implement rate limiter for debug events (1/sec max)
4. Re-profile event count

**Notes:**
- Do not rate-limit critical events (hit confirmations, state changes)
- Only rate-limit debug/warning events

---

### Issue #209: Ability Activation Consolidation

**Priority:** Medium
**Labels:** `phase-4`, `networking`, `performance`, `medium`
**Depends On:** #189, #206

**Overview:**
Consolidate multiple ability-related events into single AbilityAction event. Current pattern uses separate events for cast, cancel, cooldown, causing event spam during combo chains.

**Acceptance Criteria:**
- [ ] Create single AbilityAction event with action type field (cast, cancel, cooldown)
- [ ] Migrate AbilityCastRequest, AbilityCastResult, AbilityCooldownUpdate to single event
- [ ] Profile: measure event count reduction (target: 30%+ fewer events during combo)
- [ ] Maintain all gameplay behavior

**Files Affected:**
- `src/shared/network/NetworkProvider.lua` (register new AbilityAction event)
- `src/server/services/AbilitySystem.lua` (use consolidated event)
- `src/client/controllers/AspectController.lua` (use consolidated event)

**Implementation Tasks:**
1. Profile ability event count during 10-hit combo
2. Design AbilityAction packet with action type field
3. Migrate cast/cancel/cooldown to single event
4. Re-profile event count

**Notes:**
- Action types: "cast", "cancel", "cooldown_update", "ready"

---

### Issue #210: Client-Side Prediction for Simple Actions

**Priority:** Low
**Labels:** `phase-4`, `networking`, `frontend`, `low`
**Depends On:** #206

**Overview:**
Implement client-side prediction for simple actions (movement, blocking) to reduce perceived latency. Current pattern waits for server confirmation before updating client state.

**Acceptance Criteria:**
- [ ] Client predicts block state immediately on input
- [ ] Client predicts movement state transitions (idle, walk, sprint)
- [ ] Server correction on desync (rollback prediction if server rejects)
- [ ] Profile: measure perceived input latency reduction (target: 50%+ faster feedback)
- [ ] No false feedback (block VFX without actual block)

**Files Affected:**
- `src/client/controllers/ActionController.lua` (predict block state)
- `src/client/controllers/MovementController.lua` (predict movement state)
- `src/client/controllers/StateSyncController.lua` (handle server correction)

**Implementation Tasks:**
1. Implement prediction for block state (immediate client feedback)
2. Implement server correction (rollback on reject)
3. Playtest for false positives (blocked attack shows damage)

**Notes:**
- Only predict low-risk actions (movement, blocking)
- Do not predict attacks or damage (server-authoritative)

---

## Phase 5: Client UI & Animation (Parallel with Phase 4)

**Duration:** Weeks 5-6
**Priority:** Medium
**Dependencies:** Some depend on Phase 4
**Issues:** #211-#214

### Issue #211: UI Binding Optimization

**Priority:** Medium
**Labels:** `phase-5`, `frontend`, `ui`, `medium`
**Depends On:** #206

**Overview:**
Optimize UI data binding to reduce update frequency. Current pattern may update UI every frame even when values unchanged.

**Acceptance Criteria:**
- [ ] Add change detection to UIBinding module (only update if value changed)
- [ ] Batch UI updates to max 20 Hz (not 60 Hz)
- [ ] Profile: measure UI update frequency reduction (target: 50%+ fewer updates)
- [ ] No visible UI lag

**Files Affected:**
- `src/client/modules/UIBinding.lua`
- All controllers using UIBinding (PlayerHUDController, InventoryController, etc.)

**Implementation Tasks:**
1. Profile current UI update frequency (updates per second)
2. Add change detection to UIBinding.SetText() and SetVisible()
3. Batch updates to 20 Hz (every 3 frames)
4. Re-profile update frequency
5. Playtest for UI responsiveness

**Notes:**
- Health/posture bars can update at 20 Hz without visible lag
- Critical UI (e.g., combo counter) may need higher rate

---

### Issue #212: UI Instance Recycling

**Priority:** Medium
**Labels:** `phase-5`, `frontend`, `ui`, `medium`
**Depends On:** #211

**Overview:**
Recycle UI instances instead of creating/destroying on show/hide. Current pattern may create new damage numbers, notifications each time, causing GC pressure.

**Acceptance Criteria:**
- [ ] Create UIInstancePool for damage numbers, notifications
- [ ] Pool sized for peak usage (e.g., 20 damage numbers)
- [ ] Profile: measure GC pause reduction (target: eliminate >5ms UI pauses)
- [ ] No visual artifacts from instance reuse

**Files Affected:**
- `src/client/modules/UIInstancePool.lua` (create new)
- `src/client/controllers/CombatFeedbackUI.lua` (use pool for damage numbers)
- `src/shared/modules/ui/NotificationService.lua` (use pool for notifications)

**Implementation Tasks:**
1. Profile GC pauses during UI-heavy scenarios
2. Create UIInstancePool with Get() and Return()
3. Replace Instance.new() in damage numbers with pool.Get()
4. Replace Instance.new() in notifications with pool.Get()
5. Re-profile GC pauses

**Notes:**
- Pool pre-allocated on Init()
- Return() must reset properties (Text, Position, Color, Transparency)

---

### Issue #213: Animation Preloading & Asset Validation

**Priority:** Low
**Labels:** `phase-5`, `frontend`, `animation`, `low`

**Overview:**
Validate animation preloading strategy and add asset validation. Current pattern calls PreloadAll() but doesn't validate load success.

**Acceptance Criteria:**
- [ ] AnimationLoader: Add validation that all assets loaded successfully
- [ ] Log warnings for stub assets (rbxassetid://0)
- [ ] Profile: measure animation load time (document baseline)
- [ ] Add retry logic for failed preloads (transient network errors)

**Files Affected:**
- `src/shared/modules/AnimationLoader.lua`

**Implementation Tasks:**
1. Add success validation to PreloadAsync()
2. Log warnings for stub assets
3. Implement retry logic (max 3 retries)
4. Profile load time

**Notes:**
- Preload during LoadingController to hide latency
- Stub assets (rbxassetid://0) should warn but not error

---

### Issue #214: HUD Update Queue & Batching

**Priority:** Low
**Labels:** `phase-5`, `frontend`, `ui`, `low`
**Depends On:** #211

**Overview:**
Batch HUD updates into single frame update instead of multiple per-frame updates. Current pattern may update health bar, posture bar, stamina bar separately in same frame.

**Acceptance Criteria:**
- [ ] PlayerHUDController: Queue updates, apply once per frame
- [ ] Profile: measure UI update call reduction (target: 30%+ fewer SetProperty calls)
- [ ] No visible batching artifacts

**Files Affected:**
- `src/client/controllers/PlayerHUDController.lua`

**Implementation Tasks:**
1. Profile UI property set call frequency
2. Add update queue to PlayerHUDController
3. Flush queue once per frame (RenderStepped)
4. Re-profile call frequency

**Notes:**
- Queue deduplication: if health queued twice in same frame, apply only final value

---

## Dependency Graph Summary

```
Phase 1 (Foundation) - No dependencies, start immediately:
  #189 Service Require Refactoring
  #190 Attribute Caching
  #191 Centralized Tick Loops
  #192 Movement State Machine Caching
  #193 Debug Systems Gating
  #194 Module Initialization Audit

Phase 2 (Combat) - Depends on Phase 1:
  #195 Hitbox Lifetime Tuning → depends #189, #191
  #196 Batch Hitbox Checks → depends #189, #195
  #197 Movement Optimization → depends #192
  #198 Posture Caching → depends #190, #192
  #199 Combat Per-Hit → depends #189, #190

Phase 3 (Rendering) - Independent, can start immediately:
  #200 Minimal VFX
  #201 Particle Pool → depends #200
  #202 Ambient Culling
  #203 LOD Optimization
  #204 Invisible Parts → depends #203
  #205 Rendering Report → depends #200-#204

Phase 4 (Network) - Depends on Phase 1:
  #206 Snapshot Architecture → depends #189
  #207 Data Quantization → depends #206
  #208 Rate-Limited Logging → depends #193, #206
  #209 Ability Consolidation → depends #189, #206
  #210 Client Prediction → depends #206

Phase 5 (UI) - Some depend on Phase 4:
  #211 UI Binding Optimization → depends #206
  #212 UI Instance Recycling → depends #211
  #213 Animation Preloading (independent)
  #214 HUD Batching → depends #211
```

---

## Rollout Strategy

### Week 1-2: Foundation (Phase 1)
- Issues #189-#194
- Goal: Establish performance baseline, unblock Phase 2 & 4
- Can parallelize all 6 issues (no inter-dependencies)

### Week 3-4: Combat + Rendering (Phases 2 & 3)
- Issues #195-#205
- Phase 2 starts after Phase 1 completes
- Phase 3 can start immediately (independent)
- Goal: Optimize hot paths (combat, hitbox) and client rendering

### Week 5-6: Network + UI (Phases 4 & 5)
- Issues #206-#214
- Phase 4 starts after Phase 1 completes
- Phase 5 starts after Phase 4 snapshot work completes
- Goal: Reduce network bandwidth, optimize client UI

---

## Testing Strategy

**Per-Issue Testing:**
- [ ] Profile before/after with Studio Microprofiler
- [ ] Document improvement percentage in issue comment
- [ ] Manual gameplay test (no behavior changes)
- [ ] Verify zero type errors with `--!strict`

**Per-Phase Testing:**
- [ ] Stress test: 100-player simulation (if possible)
- [ ] Low-end device test: Graphics Quality 1-3
- [ ] Performance regression test: compare against baseline

**Final Integration Testing:**
- [ ] Full epic profiling: compare Week 1 vs Week 12
- [ ] Document improvements in `docs/OPTIMIZATION_RESULTS.md`
- [ ] Verify all success metrics achieved

---

## Commit Convention

All commits reference sub-issue number:

```bash
git commit -m "#189: Refactor service requires in ability modules

- Moved CombatService, DummyService requires to module scope
- Removed per-hit pcall(require(...)) in OnHit callbacks
- Profiled: 15% reduction in combat loop frame time
"
```

---

## Success Criteria

Epic considered complete when:
- [ ] All 26 sub-issues closed
- [ ] All acceptance criteria met per issue
- [ ] Success metrics achieved:
  - [ ] Server frame time <5ms for 100 players (30%+ reduction)
  - [ ] Per-hit execution <0.5ms
  - [ ] Network bandwidth reduced 40%+
  - [ ] Client maintains 60+ FPS on target devices
  - [ ] No GC spikes >16ms
  - [ ] Memory peak reduced 15%+
- [ ] No gameplay behavior changes (verified by QA)
- [ ] Performance results documented in `docs/OPTIMIZATION_RESULTS.md`

---

## Contact

**Epic Owner:** Development Team
**Tracking:** GitHub Issues #189-#214
**Questions:** Reference this document and individual issue descriptions
