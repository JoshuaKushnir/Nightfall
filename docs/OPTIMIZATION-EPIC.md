# 🚀 Nightfall Optimization Epic

**Epic Title:** Comprehensive Server & Client Performance Optimization  
**Epic Issue:** #XXX (TBD - Create main epic in GitHub)  
**Priority:** High  
**Scope:** Multi-phase optimization spanning server logic, rendering, networking, and client UI  
**Status:** Planning Phase

---

## 📋 Epic Overview

This epic consolidates all performance optimization work across Nightfall's codebase, targeting:

- **Server overhead reduction** (per-frame logic, attribute churn, module require cycles)
- **Combat system efficiency** (hitbox tuning, posture/stamina caching, state machine optimization)
- **Visual & rendering cost** (VFX reuse, particle optimization, model LOD, ambient effect culling)
- **Network bandwidth lean** (event-level snapshots, data quantization, rate limiting)
- **Client UI/animation stability** (binding optimization, animation preloading, UI recycling)

**Goal:** Achieve consistent 60+ FPS on target devices while maintaining visual fidelity and gameplay responsiveness.

---

## 🎯 Phase Breakdown

### Phase 1: Server & Core Logic Optimizations (Foundation)
**Blocker for:** Phase 2, Phase 4  
**Estimated Issues:** 6  

### Phase 2: Hitbox & Combat Tuning (Depends on Phase 1)
**Blocker for:** Phase 3  
**Estimated Issues:** 5  

### Phase 3: VFX, Models & Map Polish (Parallel with Phase 2)
**Estimated Issues:** 6  

### Phase 4: Network & Replication Lean (Depends on Phase 1)
**Estimated Issues:** 5  

### Phase 5: Client UI & Animation (Parallel with Phase 4)
**Estimated Issues:** 4  

---

## 📍 Phase 1: Server & Core Logic Optimizations

### 1.1: Service Require Refactoring – Eliminate Per-Hit pcall(require(...))
**Issue Link:** #XXX-1.1  
**Status:** Not Started  
**Priority:** Critical  
**Assigns:** @engineer  

**Description:**

Move all `pcall(require(...))` calls outside of tight callbacks like `OnHit`, `OnActivate`, etc.

**Requirements:**
- Audit all ability modules for per-hit/per-frame require calls
- Cache service references at module initialization
- Refactor CombatService, DummyService, PostureService, HitboxService into module-level requires
- Test zero-allocation in combat loops

**Files to Touch:**
- `src/server/abilities/**/*.lua` (all ability modules)
- `src/server/services/CombatService.lua`
- `src/server/services/DummyService.lua`

**Tests:**
- Profile before/after with game profiler
- Ensure no runtime errors in ability callbacks

**Acceptance Criteria:**
- All ability modules require services once at top level
- No per-frame require calls detected in grep search
- Combat loop execution time reduced by 10%+

---

### 1.2: Attribute Caching in Tight Loops (Burning, CinderField, Grey Veil)
**Issue Link:** #XXX-1.2  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1  
**Assigns:** @engineer  

**Description:**

Reduce SetAttribute/GetAttribute churn in periodic effect ticks by caching values locally and writing back only on state change.

**Requirements:**
- Refactor Burning tick loop to cache HP, heat, damage locally
- Cache CinderField aura radius and scaling per tick
- Cache Grey Veil posture drain rate per character
- Batch writes to attributes on effect tick end

**Files to Touch:**
- `src/server/abilities/Ember.lua`
- `src/server/abilities/Cinderfield.lua`
- `src/server/abilities/GreyVeil.lua`
- `src/server/services/EffectRunner.lua`

**Tests:**
- Log attribute read/write counts per tick
- Verify effect application is still correct

**Acceptance Criteria:**
- SetAttribute calls reduced by 50%+ in effect ticks
- No observable gameplay change in effect timing
- Memory allocations in effect loops reduced

---

### 1.3: Centralized Tick Loop for Periodic Effects
**Issue Link:** #XXX-1.3  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1, #XXX-1.2  
**Assigns:** @engineer  

**Description:**

Replace many small `task.spawn` / `task.delay` loops per target with a single global tick manager that batches all periodic effects.

**Requirements:**
- Create TickManager service to batch Burning, aura ticks, zone effects, etc.
- Register/deregister effects rather than spawning per-target loops
- Ensure tick order is deterministic and matches current behavior
- Profile memory usage and frame time

**Files to Touch:**
- `src/server/services/TickManager.lua` (new)
- `src/server/services/EffectRunner.lua`
- `src/server/abilities/Ember.lua`
- `src/server/abilities/Cinderfield.lua`

**Tests:**
- Run 100 targets with burning status; verify tick frequency and damage
- No visual change in effect timing from player perspective

**Acceptance Criteria:**
- Single global tick loop handles all periodic effects
- Spawned task count reduced by 80%+
- Memory usage per active effect reduced

---

### 1.4: Cache Movement Config & State Machine Optimization
**Issue Link:** #XXX-1.4  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1  
**Assigns:** @engineer  

**Description:**

Cache HumanoidRootPart, Humanoid, and movement config values once per state entry rather than querying every frame.

**Requirements:**
- Audit all movement state modules (wallrun, vault, slide, ledge catch, etc.)
- Cache local references to character parts on state entry
- Cache DisciplineConfig lookups (O(1) dictionary access, not recomputation)
- Ensure cache invalidation on character respawn

**Files to Touch:**
- `src/server/movement/**/*.lua` (all state modules)
- `src/shared/DisciplineConfig.lua`

**Tests:**
- Profile movement loop execution time per state
- Verify no dangling references on respawn

**Acceptance Criteria:**
- Movement state frame time reduced by 15%+
- No memory leaks on respawn
- All config lookups are O(1)

---

### 1.5: Disable Debug Systems in Production
**Issue Link:** #XXX-1.5  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** None  
**Assigns:** @engineer  

**Description:**

Audit and gate all debug systems behind `RunMode` checks. Disable in live servers:
- ShowHitboxes
- ShowNetworkEvents
- Slow-motion controls
- Dummy spawners
- Admin commands (or gate by player ID)
- Verbose logging

**Requirements:**
- Add RunMode enum (dev, staging, production)
- Wrap all debug output in `if RunMode == "dev" then`
- Audit for stray print/warn statements
- Ensure no debug variables left in production code

**Files to Touch:**
- `src/server/Config.lua` (or new RunMode.lua)
- `src/server/**/*.lua` (audit)
- `src/client/**/*.lua` (audit)

**Tests:**
- Run on production RunMode and verify no debug output
- Check memory allocation per frame on production vs dev

**Acceptance Criteria:**
- All debug systems toggleable via RunMode
- Zero debug output on production RunMode
- GC spikes from logging eliminated

---

### 1.6: Module Initialization & Require Order Audit
**Issue Link:** #XXX-1.6  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-1.1  
**Assigns:** @engineer  

**Description:**

Ensure modules are required in correct order, no circular dependencies, and module initialization is minimal (no expensive logic in module scope).

**Requirements:**
- Audit require order in main entry points
- Document dependency graph
- Move expensive initialization to functions/services
- Run require cycle detection

**Files to Touch:**
- `src/server/main.lua`
- `src/client/main.lua`
- All service files

**Tests:**
- Run cycle detection on codebase
- Measure module load time before/after

**Acceptance Criteria:**
- Zero circular dependencies
- Module load time under 100ms total
- All service initialization is lazy or deferred

---

## 📍 Phase 2: Hitbox & Combat Tuning

### 2.1: Hitbox Lifetime & Size Tuning
**Issue Link:** #XXX-2.1  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1  
**Assigns:** @engineer  

**Description:**

Audit hitbox configurations to reduce target checks and memory churn.

**Requirements:**
- Review all ability hitbox definitions for lifetime ≤0.2s (where gameplay allows)
- Reduce default hitbox sizes where collision permits
- Audit CanHitTwice usage; disable where not essential
- Document hitbox lifetime justification per ability

**Files to Touch:**
- `src/server/abilities/**/*.lua` (all ability configs)
- `src/server/services/HitboxService.lua`

**Tests:**
- Profile target check time per ability
- Verify no unintended immunity issues from lifetime reduction

**Acceptance Criteria:**
- Average hitbox lifetime reduced to 0.15s where possible
- Hitbox count per frame reduced by 20%+
- No gameplay complaints in internal testing

---

### 2.2: Batch Hitbox Checks for Training Dummies & PvE
**Issue Link:** #XXX-2.2  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1, #XXX-2.1  
**Assigns:** @engineer  

**Description:**

Implement region queries or batch checks instead of individual hitbox spawns for training dummies and PvE encounters.

**Requirements:**
- Create BatchHitboxService or region-based detection system
- Refactor DummyService to use batch checks
- Refactor PvE enemy abilities to use region queries
- Ensure detection accuracy matches per-frame checks

**Files to Touch:**
- `src/server/services/HitboxService.lua`
- `src/server/services/DummyService.lua` (new BatchHitboxService)
- `src/server/enemies/**/*.lua`

**Tests:**
- Profile batch check time vs individual hitbox spawn
- Test collision accuracy on dummies with high-frequency attacks

**Acceptance Criteria:**
- Batch checks are 3x faster than individual spawns for same accuracy
- DummyService frame time reduced by 40%+

---

### 2.3: Movement State Machine Optimization
**Issue Link:** #XXX-2.3  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.4  
**Assigns:** @engineer  

**Description:**

Ensure movement state machine only updates when active; cache state config and part references.

**Requirements:**
- Audit all movement states for unnecessary per-frame work
- Cache state config lookups on state entry
- Add early exits for inactive states
- Profile state machine execution time

**Files to Touch:**
- `src/server/movement/**/*.lua` (all state modules)
- `src/server/movement/StateMachine.lua`

**Tests:**
- Profile frame time with many active movement states
- Verify state transitions are still responsive

**Acceptance Criteria:**
- Inactive state execution time near zero
- Active state execution time reduced by 20%+

---

### 2.4: Posture & Stamina/Breath Caching
**Issue Link:** #XXX-2.4  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-1.2, #XXX-1.4  
**Assigns:** @engineer  

**Description:**

Cache DisciplineConfig lookups and stamina/breath calculations; avoid recomputation every frame.

**Requirements:**
- Profile stamina/breath drain calculations per frame
- Cache drain rates per character at session start
- Cache recovery rates from DisciplineConfig (O(1) lookups)
- Batch stamina/breath updates per tick instead of per-frame

**Files to Touch:**
- `src/shared/DisciplineConfig.lua`
- `src/server/services/PostureService.lua`

**Tests:**
- Verify stamina/breath drain rates match spec exactly
- Profile calculation time per frame

**Acceptance Criteria:**
- Stamina/breath calculation time reduced by 50%+
- No observable timing change in stamina drain

---

### 2.5: Combat Service Per-Hit Optimization
**Issue Link:** #XXX-2.5  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1, #XXX-1.2  
**Assigns:** @engineer  

**Description:**

Optimize CombatService hit processing loop: cache player data, reduce attribute churn, batch damage application.

**Requirements:**
- Cache target character data (health, armor, resists) on hit callback entry
- Reduce SetAttribute calls for damage application
- Batch damage calculations before network send
- Profile per-hit execution time

**Files to Touch:**
- `src/server/services/CombatService.lua`

**Tests:**
- Run high-frequency ability combos (100+ hits/sec)
- Verify damage numbers and effects still apply correctly

**Acceptance Criteria:**
- Per-hit execution time under 0.5ms
- CombatService frame time reduced by 30%+

---

## 📍 Phase 3: VFX, Models & Map Polish

### 3.1: Convert Design-Only VFX to Minimal Cheap Effects
**Issue Link:** #XXX-3.1  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** None  
**Assigns:** @designer, @engineer  

**Description:**

Convert VFX marked as "design-only" or "stub" into minimal, cheap effects with few particles and short lifetimes.

**Requirements:**
- Audit all VFX hooks in ability modules for stub comments
- Replace stubs with minimal ParticleEmitter configs (5-10 particles, 0.2-0.5s lifetime)
- Document intended visual effect in comment
- Test on low-end device (mobile)

**Files to Touch:**
- `src/client/effects/**/*.lua`
- `src/server/abilities/**/*.lua` (VFX hook descriptions)

**Tests:**
- Run on low-end device; measure VFX frame time
- Visual QA pass on each effect

**Acceptance Criteria:**
- All stub VFX replaced with cheap implementations
- VFX frame time on low-end device under 5ms total
- Visual feedback still clear and responsive

---

### 3.2: Particle Emitter Reuse Pool
**Issue Link:** #XXX-3.2  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-3.1  
**Assigns:** @engineer  

**Description:**

Create emitter pool to reuse ParticleEmitters instead of destroying/creating on each cast.

**Requirements:**
- Create EffectPool service for emitter pooling
- Implement acquire/release cycle
- Update all ability VFX to use pooled emitters
- Ensure no emitter state leaks between uses

**Files to Touch:**
- `src/client/services/EffectPool.lua` (new)
- `src/client/effects/**/*.lua` (integrate pool)

**Tests:**
- Profile GC time with/without pooling
- Verify no visual glitches from emitter reuse

**Acceptance Criteria:**
- Emitter instantiation reduced by 90%+
- GC spike on ability cast eliminated
- Memory fragmentation reduced

---

### 3.3: Distance-Based Ambient Effect Culling
**Issue Link:** #XXX-3.3  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** None  
**Assigns:** @engineer  

**Description:**

Gate always-on ambient emitters (fog, smoke, environmental effects) by distance from player camera.

**Requirements:**
- Identify all always-on ambient effect emitters
- Add distance checks; disable emitters >100 studs away
- Re-enable on approach
- Verify visual pop-in is acceptable

**Files to Touch:**
- `src/client/environment/**/*.lua`
- `src/client/services/CameraService.lua` (query camera distance)

**Tests:**
- Measure FPS improvement with all ambient effects at max distance
- Walk around world and test for obvious pop-in

**Acceptance Criteria:**
- Ambient emitter count reduced by 70%+ at distance
- FPS improvement of 5-10% in dense VFX areas
- No distracting visual pop-in

---

### 3.4: Model Polygon Count & LOD Optimization
**Issue Link:** #XXX-3.4  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** None  
**Assigns:** @designer, @engineer  

**Description:**

Reduce polygon counts on background meshes; implement LOD or simpler variants for far objects.

**Requirements:**
- Audit background mesh poly counts (buildings, cliffs, trees, etc.)
- Target 50% reduction on far-visible objects
- Implement LOD swap at distance thresholds or use SimpleMesh variants
- Test on low-end device

**Files to Touch:**
- `Nightfall.rbxlx` (workspace/map assets)

**Tests:**
- Run rendering profiler; measure poly count before/after
- FPS comparison on low-end device

**Acceptance Criteria:**
- Background mesh count reduced by 50%+ at distance
- FPS improvement of 10%+ in dense areas
- No visible quality loss in combat zones

---

### 3.5: Remove Invisible & Overlapping Parts
**Issue Link:** #XXX-3.5  
**Status:** Not Started  
**Priority:** Low  
**Depends On:** #XXX-3.4  
**Assigns:** @designer  

**Description:**

Audit and remove invisible, overlapping, or redundant union parts from map and models.

**Requirements:**
- Scan for invisible parts (`CanCollide=false`, `Transparency=1`)
- Identify overlapping geometry
- Remove or merge redundant unions
- Test collision behavior remains correct

**Files to Touch:**
- `Nightfall.rbxlx` (workspace/map assets)

**Tests:**
- Verify walkable areas unchanged
- Test collision on merged/removed areas

**Acceptance Criteria:**
- All invisible/redundant parts removed
- Part count reduced by 10%+
- Collision behavior unchanged

---

### 3.6: Rendering Cost Profiling & Optimization Report
**Issue Link:** #XXX-3.6  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-3.1 through #XXX-3.5  
**Assigns:** @engineer  

**Description:**

Run comprehensive rendering profiler and generate report with optimization recommendations.

**Requirements:**
- Use Roblox profiler to measure rendering time
- Identify top 10 bottlenecks (VFX, models, transparency, etc.)
- Document findings and recommend next steps
- Update README with rendering best practices

**Files to Touch:**
- `docs/RENDERING-OPTIMIZATION-REPORT.md` (new)

**Tests:**
- Profile on low-end, mid-range, and high-end devices

**Acceptance Criteria:**
- Report identifies all >5% frame time contributors
- Recommendations are actionable
- FPS improvement on target devices ≥20%

---

## 📍 Phase 4: Network & Replication Lean

### 4.1: Event-Level Snapshot Architecture
**Issue Link:** #XXX-4.1  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1  
**Assigns:** @engineer  

**Description:**

Refactor StateSyncController/Service to send high-level event snapshots at fixed intervals instead of per-frame or per-change.

**Requirements:**
- Define snapshot schema (position, health, posture, state)
- Implement fixed-rate snapshot sends (e.g., 10-20 Hz)
- Compress snapshots using quantization
- Ensure client reconciliation is smooth

**Files to Touch:**
- `src/server/services/StateSyncService.lua`
- `src/client/controllers/StateSyncController.lua`
- `src/shared/network/Packets.lua`

**Tests:**
- Measure network bandwidth before/after
- Test client-side animation smoothness with snapshot rate

**Acceptance Criteria:**
- Network bandwidth reduced by 40%+
- Snapshot rate configurable (no hardcoded values)
- Visual latency unchanged (smooth interpolation)

---

### 4.2: Data Quantization for Network Compression
**Issue Link:** #XXX-4.2  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-4.1  
**Assigns:** @engineer  

**Description:**

Quantize network data (positions, health, posture) to send fewer bits per update.

**Requirements:**
- Implement position quantization (e.g., round to 0.1 studs)
- Quantize health/posture to 0-255 range
- Quantize rotation to 256 values
- Verify quantization error is imperceptible

**Files to Touch:**
- `src/shared/network/Compression.lua` (new)
- `src/shared/network/Packets.lua`

**Tests:**
- Measure bandwidth reduction per quantization scheme
- Verify no observable gameplay glitches

**Acceptance Criteria:**
- Packet sizes reduced by 30%+
- Quantization error <0.1 studs (position), <1% (health/posture)

---

### 4.3: Rate-Limited Logging & Debug Events
**Issue Link:** #XXX-4.3  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-1.5, #XXX-4.1  
**Assigns:** @engineer  

**Description:**

Implement rate limiting on verbose logging and debug events to prevent GC spikes and bandwidth bloat.

**Requirements:**
- Audit all network debug event sends
- Add throttle/skip logic (e.g., 1 log per 10 frames)
- Cache log strings to reduce allocations
- Gate debug events behind RunMode

**Files to Touch:**
- `src/server/services/NetworkService.lua`
- `src/client/services/NetworkService.lua`

**Tests:**
- Measure GC time with/without debug logging
- Verify critical debug info is still visible (at reduced frequency)

**Acceptance Criteria:**
- Debug event frequency reduced by 90%+
- GC spikes from logging eliminated
- No performance regression in core systems

---

### 4.4: Ability Activation Networking
**Issue Link:** #XXX-4.4  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-1.1, #XXX-4.1  
**Assigns:** @engineer  

**Description:**

Ensure ability activation sends single high-level request event, not per-frame inputs or redundant "still holding" messages.

**Requirements:**
- Audit all ability activation sends
- Consolidate multiple sends into single AbilityCastRequest
- Remove "still holding" events; use local client prediction
- Server validates once, applies once

**Files to Touch:**
- `src/client/controllers/AbilityController.lua`
- `src/server/services/NetworkService.lua`

**Tests:**
- Profile network traffic during combo sequences
- Verify server receives exactly one request per activation

**Acceptance Criteria:**
- Ability request packets reduced by 80%+
- No duplicate ability activations
- Network latency impact unchanged

---

### 4.5: Client-Side Prediction for Simple Actions
**Issue Link:** #XXX-4.5  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-4.1  
**Assigns:** @engineer  

**Description:**

Let clients predict simple actions locally (blocking, hit-react animations, posture bar easing) and reconcile with server.

**Requirements:**
- Implement local client block prediction
- Predict hit-react animations (no network send)
- Predict posture bar easing animations
- Server sends authoritative updates; client smoothly transitions
- Handle mispredictions gracefully

**Files to Touch:**
- `src/client/controllers/CombatController.lua`
- `src/client/ui/PostureBar.lua`

**Tests:**
- Test block prediction accuracy with network lag
- Verify no visual glitches on misprediction

**Acceptance Criteria:**
- Block feedback is instant on client
- Posture bar feels responsive
- Misprediction corrections are smooth (no jarring snaps)

---

## 📍 Phase 5: Client UI & Animation

### 5.1: UI Binding Optimization
**Issue Link:** #XXX-5.1  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-4.1  
**Assigns:** @engineer  

**Description:**

Ensure UI bindings are not recalculating expensive functions every Heartbeat; keep lambdas simple.

**Requirements:**
- Audit UIBinding usage in all UI modules
- Identify expensive lambdas (lookups, allocations, string ops)
- Move expensive logic to batch update queue
- Cache frequently accessed values

**Files to Touch:**
- `src/client/ui/**/*.lua` (audit all bindings)
- `src/client/services/UIBindingService.lua`

**Tests:**
- Profile lambda execution time per binding
- Measure GC allocation per Heartbeat

**Acceptance Criteria:**
- Lambda execution time <0.1ms per binding
- No allocations in hot-path lambdas
- UI update queue batches 80%+ of updates

---

### 5.2: UI Instance Recycling
**Issue Link:** #XXX-5.2  
**Status:** Not Started  
**Priority:** High  
**Depends On:** #XXX-5.1  
**Assigns:** @engineer  

**Description:**

Implement recycling pool for UI frames, damage numbers, tooltips, etc. instead of create/destroy cycle.

**Requirements:**
- Create UIRecycler service for common UI elements
- Refactor damage number displays to use recycled frames
- Refactor tooltip displays to use recycled instances
- Ensure state cleanup between reuses

**Files to Touch:**
- `src/client/services/UIRecycler.lua` (new)
- `src/client/ui/DamageNumber.lua`
- `src/client/ui/Tooltip.lua`

**Tests:**
- Measure UI instance count during gameplay
- Verify no visual glitches from reuse

**Acceptance Criteria:**
- UI instance count reduced by 80%+
- GC time from UI creation/destruction eliminated
- Memory fragmentation reduced

---

### 5.3: Animation Preloading & Asset Validation
**Issue Link:** #XXX-5.3  
**Status:** Not Started  
**Priority:** High  
**Depends On:** None  
**Assigns:** @engineer  

**Description:**

Call AnimationLoader.PreloadAll on character spawn to avoid mid-fight stutters from animation load. Validate all assets are real rbxassetid values.

**Requirements:**
- Implement PreloadAll call on spawn
- Audit all animation assets for `rbxassetid0` stubs
- Replace all stubs with real asset IDs
- Profile animation load time

**Files to Touch:**
- `src/client/animation/AnimationLoader.lua`
- `src/client/controllers/CharacterController.lua`
- `src/server/abilities/**/*.lua` (asset ID audit)

**Tests:**
- Preload all combat animations; measure load time
- Profile for stutters during first ability use

**Acceptance Criteria:**
- All animations preloaded before combat (zero stubs)
- No animation load stutters mid-fight
- Load time <500ms total

---

### 5.4: HUD Update Queue & Batching
**Issue Link:** #XXX-5.4  
**Status:** Not Started  
**Priority:** Medium  
**Depends On:** #XXX-5.1  
**Assigns:** @engineer  

**Description:**

Batch HUD updates via centralized queue instead of individual property sets; use HUDLayout, HUDTheme for styling consistency.

**Requirements:**
- Implement HUDUpdateQueue service
- Consolidate property updates into batch sends
- Use HUDTheme for all color/styling
- Update HUDLayout for all element positioning

**Files to Touch:**
- `src/client/services/HUDUpdateQueue.lua` (new)
- `src/client/ui/HUDLayout.lua`
- `src/client/ui/HUDTheme.lua`
- `src/client/ui/**/*.lua` (integrate queue)

**Tests:**
- Profile property set count per Heartbeat
- Measure HUD responsiveness with queue batching

**Acceptance Criteria:**
- Property sets batched into single queue update
- Visual update latency <1 frame
- Code consistency across all HUD elements

---

## 🔗 Dependencies & Blockers

```
Phase 1 (Foundation)
  ├─ 1.1 (Service Require Refactoring)
  │   └─ BLOCKS: 1.2, 1.3, 1.5, 2.1, 2.2, 2.5
  ├─ 1.2 (Attribute Caching)
  │   └─ BLOCKS: 1.3, 2.5
  ├─ 1.3 (Centralized Tick Loop)
  │   └─ DEPENDS: 1.1, 1.2
  ├─ 1.4 (Movement Caching)
  │   └─ BLOCKS: 2.3, 2.4
  ├─ 1.5 (Debug Systems)
  │   └─ BLOCKS: 4.3
  └─ 1.6 (Module Initialization)

Phase 2 (Combat)
  ├─ 2.1 (Hitbox Tuning)
  │   └─ DEPENDS: 1.1
  ├─ 2.2 (Batch Hitbox Checks)
  │   └─ DEPENDS: 1.1, 2.1
  ├─ 2.3 (Movement State Machine)
  │   └─ DEPENDS: 1.4
  ├─ 2.4 (Posture & Stamina)
  │   └─ DEPENDS: 1.2, 1.4
  └─ 2.5 (CombatService Optimization)
      └─ DEPENDS: 1.1, 1.2

Phase 3 (VFX & Rendering)
  ├─ 3.1 (Minimal Cheap VFX)
  ├─ 3.2 (Emitter Reuse Pool)
  │   └─ DEPENDS: 3.1
  ├─ 3.3 (Ambient Culling)
  ├─ 3.4 (LOD Optimization)
  ├─ 3.5 (Invisible Parts Removal)
  │   └─ DEPENDS: 3.4
  └─ 3.6 (Rendering Report)
      └─ DEPENDS: 3.1-3.5

Phase 4 (Network)
  ├─ 4.1 (Event Snapshot Architecture)
  │   └─ DEPENDS: 1.1
  ├─ 4.2 (Data Quantization)
  │   └─ DEPENDS: 4.1
  ├─ 4.3 (Rate-Limited Logging)
  │   └─ DEPENDS: 1.5, 4.1
  ├─ 4.4 (Ability Activation Networking)
  │   └─ DEPENDS: 1.1, 4.1
  └─ 4.5 (Client Prediction)
      └─ DEPENDS: 4.1

Phase 5 (UI & Animation)
  ├─ 5.1 (UI Binding Optimization)
  │   └─ DEPENDS: 4.1
  ├─ 5.2 (UI Instance Recycling)
  │   └─ DEPENDS: 5.1
  ├─ 5.3 (Animation Preloading)
  ├─ 5.4 (HUD Update Queue)
      └─ DEPENDS: 5.1
```

---

## 📊 Tracking & Status

| Phase | Issue Count | Status | Start Date | Est. Completion | Notes |
|-------|-------------|--------|------------|-----------------|-------|
| Phase 1 | 6 | Not Started | TBD | TBD | Critical foundation; blocks all others |
| Phase 2 | 5 | Blocked | TBD | TBD | Depends on Phase 1 completion |
| Phase 3 | 6 | Not Started | TBD | TBD | Can run in parallel with Phase 2 |
| Phase 4 | 5 | Blocked | TBD | TBD | Depends on Phase 1 completion |
| Phase 5 | 4 | Not Started | TBD | TBD | Can run in parallel with Phase 4 |
| **Total** | **26** | **Planning** | **TBD** | **TBD** | Estimated 8-12 weeks |

---

## 🎯 Success Metrics

- [ ] **Server Frame Time:** Reduce per-frame overhead by 30%+ (target: <5ms for 100 players)
- [ ] **Combat Overhead:** Per-hit execution time <0.5ms (from current ~2-3ms)
- [ ] **Network Bandwidth:** Reduce data sent per player by 40%+ (quantization + snapshots)
- [ ] **Client FPS:** Maintain 60+ FPS on target devices (low-end: mid-range: high-end)
- [ ] **GC Spikes:** Eliminate GC pauses >16ms during normal gameplay
- [ ] **Memory Usage:** Reduce peak memory allocation by 15%+
- [ ] **Visual Fidelity:** Zero perceptible loss in visual quality on low-end devices

---

## 📝 Implementation Notes

### Commit Convention
All work on this epic **must reference a sub-issue** in the commit message:

```
git commit -m "#XXX-1.1: Refactor service requires in ability modules

- Moved CombatService, DummyService requires to module scope
- Removed per-hit pcall(require(...)) in OnHit callbacks
- Profiled: 15% reduction in combat loop frame time
"
```

### Code Review Checklist
- [ ] Sub-issue referenced in commit
- [ ] Performance improvement measured (before/after profiling)
- [ ] No new GC allocations in hot paths
- [ ] All debug systems behind RunMode check
- [ ] Unit tests pass; no regressions
- [ ] docs/session-log.md updated with session summary

### Testing Before Merge
- [ ] Profile on low-end device (target: 60+ FPS)
- [ ] Profile on high-end device (verify no regression)
- [ ] Load test with 100+ players/NPCs (measure total frame time)
- [ ] Verify no gameplay behavior changes

---

## 🚀 Rollout Plan

1. **Phase 1 completion** → merge to main branch with feature flag
2. **Phase 2-4 completion** → enable by default; monitor telemetry
3. **Phase 5 completion** → full rollout; deprecate old systems
4. **Post-rollout** → gather player feedback; iterate on any regressions

---

## 📚 Related Issues

- Previous optimization discussions: (link to any existing issues)
- Rendering profiler results: (link to reports)
- Network analysis: (link to bandwidth reports)

---

**Last Updated:** [Date]  
**Epic Owner:** [@engineer]  
**Contributors:** [@engineer], [@designer]
