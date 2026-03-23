# 🚀 Optimization Epic: GitHub Issue Summary

**Epic Issue:** #188  
**Total Sub-Issues:** 26  
**Status:** Planning Phase  
**Created:** Today

---

## Quick Navigation

| Phase | Issues | Total | Start Date | Status |
|-------|--------|-------|------------|--------|
| **Phase 1** (Foundation) | #189-194 | 6 | Ready to Start | Not Started |
| **Phase 2** (Combat) | #195-199 | 5 | After Phase 1 | Blocked |
| **Phase 3** (VFX) | #200-205 | 6 | Can Start Now | Not Started |
| **Phase 4** (Network) | #206-210 | 5 | After Phase 1 | Blocked |
| **Phase 5** (UI) | #211-214 | 4 | Can Start Now | Not Started |
| **TOTAL** | **188-214** | **26** | **TBD** | **Planning** |

---

## Epic #188: Comprehensive Server & Client Performance Optimization

**Link:** https://github.com/JoshuaKushnir/Nightfall/issues/188

**Description:** Multi-phase optimization epic spanning server logic, rendering, networking, and client UI to reduce per-frame overhead by 30%+, network bandwidth by 40%+, and maintain 60+ FPS on target devices.

**Success Metrics:**
- ✅ Server frame time: 30%+ reduction (target <5ms for 100 players)
- ✅ Per-hit execution: <0.5ms (from ~2-3ms current)
- ✅ Network bandwidth: 40%+ reduction
- ✅ Client FPS: Maintain 60+ on target devices
- ✅ GC spikes: Eliminate >16ms pauses
- ✅ Memory peak: 15%+ reduction

---

## Phase 1: Server & Code Optimizations (Foundation)

**Status:** Ready to Start  
**Blocker for:** Phases 2, 4, and partial Phase 5  
**Estimated Duration:** 2 weeks

### Sub-Issues

#### #189: Service Require Refactoring – Eliminate Per-Hit pcall(require(...))
https://github.com/JoshuaKushnir/Nightfall/issues/189

- Eliminate per-hit `pcall(require(...))` calls in ability callbacks
- Cache service references at module initialization
- Files: `src/server/abilities/**/*.lua`, CombatService, DummyService
- **Target:** 10%+ reduction in combat frame time

#### #190: Attribute Caching in Tight Loops (Burning, CinderField, Grey Veil)
https://github.com/JoshuaKushnir/Nightfall/issues/190

- Cache SetAttribute/GetAttribute values locally in effect ticks
- Batch writes on state change instead of every frame
- Files: Ember, Cinderfield, GreyVeil, EffectRunner
- **Target:** 50%+ reduction in attribute operations
- **Depends on:** #189

#### #191: Centralized Tick Loop for Periodic Effects
https://github.com/JoshuaKushnir/Nightfall/issues/191

- Replace many task.spawn loops with single global TickManager
- Batch Burning, aura ticks, zone effects
- Files: TickManager (new), EffectRunner, ability modules
- **Target:** 80%+ reduction in spawned tasks
- **Depends on:** #189, #190

#### #192: Cache Movement Config & State Machine Optimization
https://github.com/JoshuaKushnir/Nightfall/issues/192

- Cache HumanoidRootPart, Humanoid, movement config once per state entry
- Cache DisciplineConfig lookups (O(1))
- Files: `src/server/movement/**/*.lua`, DisciplineConfig
- **Target:** 15%+ reduction in movement frame time

#### #193: Disable Debug Systems in Production
https://github.com/JoshuaKushnir/Nightfall/issues/193

- Add RunMode enum (dev, staging, production)
- Gate all debug systems: ShowHitboxes, ShowNetworkEvents, slow-motion, logging
- Files: Config.lua, all audit files
- **Target:** Eliminate GC spikes from logging

#### #194: Module Initialization & Require Order Audit
https://github.com/JoshuaKushnir/Nightfall/issues/194

- Audit require order in entry points
- Eliminate circular dependencies
- Move expensive initialization to functions/services
- Files: main.lua (server & client), all service files
- **Target:** <100ms total module load time

---

## Phase 2: Hitbox, Combat & Movement (Depends on Phase 1)

**Status:** Blocked (awaiting Phase 1)  
**Estimated Duration:** 2 weeks  
**Can Run Parallel With:** Phase 3

### Sub-Issues

#### #195: Hitbox Lifetime & Size Tuning
https://github.com/JoshuaKushnir/Nightfall/issues/195

- Reduce hitbox lifetimes to ≤0.2s where possible
- Reduce hitbox sizes; disable CanHitTwice where not essential
- Files: `src/server/abilities/**/*.lua`, HitboxService
- **Target:** 20%+ reduction in hitbox count per frame
- **Depends on:** #189

#### #196: Batch Hitbox Checks for Training Dummies & PvE
https://github.com/JoshuaKushnir/Nightfall/issues/196

- Implement region queries or batch checks instead of individual spawns
- Refactor DummyService, PvE enemies
- Files: HitboxService, DummyService, enemy modules
- **Target:** 3x faster batch checks vs individual hitboxes
- **Depends on:** #189, #195

#### #197: Movement State Machine Optimization
https://github.com/JoshuaKushnir/Nightfall/issues/197

- Only update active states; cache state config on entry
- Add early exits for inactive states
- Files: `src/server/movement/**/*.lua`, StateMachine
- **Target:** 20%+ reduction in active state frame time
- **Depends on:** #192

#### #198: Posture & Stamina/Breath Caching
https://github.com/JoshuaKushnir/Nightfall/issues/198

- Cache stamina/breath drain rates per character
- Cache DisciplineConfig recovery rates (O(1) lookups)
- Batch updates per tick instead of per-frame
- Files: DisciplineConfig, PostureService
- **Target:** 50%+ reduction in stamina/breath calculations
- **Depends on:** #190, #192

#### #199: CombatService Per-Hit Optimization
https://github.com/JoshuaKushnir/Nightfall/issues/199

- Cache target character data on hit callback entry
- Reduce SetAttribute calls for damage
- Batch damage calculations before network send
- Files: CombatService
- **Target:** <0.5ms per-hit execution time
- **Depends on:** #189, #190

---

## Phase 3: VFX, Models & Map (Parallel with Phase 2)

**Status:** Can Start Now  
**Estimated Duration:** 2 weeks  
**No Phase 1 Dependencies**

### Sub-Issues

#### #200: Convert Design-Only VFX to Minimal Cheap Effects
https://github.com/JoshuaKushnir/Nightfall/issues/200

- Replace stub VFX with minimal ParticleEmitter configs (5-10 particles, 0.2-0.5s lifetime)
- Document intended visual effect in comments
- Test on low-end device
- Files: `src/client/effects/**/*.lua`, ability modules
- **Target:** <5ms total VFX frame time on low-end device

#### #201: Particle Emitter Reuse Pool
https://github.com/JoshuaKushnir/Nightfall/issues/201

- Create EffectPool service for emitter pooling
- Implement acquire/release cycle
- Update all ability VFX to use pooled emitters
- Files: EffectPool (new), effect modules
- **Target:** 90%+ reduction in emitter instantiation
- **Depends on:** #200

#### #202: Distance-Based Ambient Effect Culling
https://github.com/JoshuaKushnir/Nightfall/issues/202

- Gate always-on ambient emitters by distance from camera
- Disable >100 studs away, re-enable on approach
- Files: `src/client/environment/**/*.lua`, CameraService
- **Target:** 5-10% FPS improvement in dense areas

#### #203: Model Polygon Count & LOD Optimization
https://github.com/JoshuaKushnir/Nightfall/issues/203

- Reduce background mesh poly counts by 50%+
- Implement LOD variants for far objects
- Test on low-end device
- Files: Nightfall.rbxlx (workspace/map assets)
- **Target:** 10%+ FPS improvement in dense areas

#### #204: Remove Invisible & Overlapping Parts
https://github.com/JoshuaKushnir/Nightfall/issues/204

- Scan for invisible parts, overlapping geometry, redundant unions
- Remove or merge; test collision behavior
- Files: Nightfall.rbxlx
- **Target:** 10%+ reduction in part count
- **Depends on:** #203

#### #205: Rendering Cost Profiling & Optimization Report
https://github.com/JoshuaKushnir/Nightfall/issues/205

- Use Roblox profiler to identify top 10 bottlenecks
- Document findings and recommendations
- Update README with rendering best practices
- Files: docs/RENDERING-OPTIMIZATION-REPORT.md (new)
- **Target:** 20%+ FPS improvement on target devices
- **Depends on:** #200-204

---

## Phase 4: Network & Replication (Depends on Phase 1)

**Status:** Blocked (awaiting Phase 1)  
**Estimated Duration:** 2 weeks

### Sub-Issues

#### #206: Event-Level Snapshot Architecture
https://github.com/JoshuaKushnir/Nightfall/issues/206

- Refactor StateSyncService to send snapshots at fixed intervals (not per-change)
- Define snapshot schema (position, health, posture, state)
- Ensure smooth client reconciliation
- Files: StateSyncService, StateSyncController, Packets.lua
- **Target:** 40%+ reduction in network bandwidth
- **Depends on:** #189

#### #207: Data Quantization for Network Compression
https://github.com/JoshuaKushnir/Nightfall/issues/207

- Quantize positions (0.1 studs), health/posture (0-255), rotations (256 values)
- Verify imperceptible quantization error
- Files: Compression.lua (new), Packets.lua
- **Target:** 30%+ reduction in packet size
- **Depends on:** #206

#### #208: Rate-Limited Logging & Debug Events
https://github.com/JoshuaKushnir/Nightfall/issues/208

- Add throttle/skip logic to debug events (1 log per 10 frames)
- Cache log strings; gate behind RunMode
- Files: NetworkService (server & client)
- **Target:** 90%+ reduction in debug event frequency
- **Depends on:** #193, #206

#### #209: Ability Activation Networking
https://github.com/JoshuaKushnir/Nightfall/issues/209

- Consolidate ability sends into single AbilityCastRequest per activation
- Remove "still holding" messages; use client prediction
- Server validates & applies once
- Files: AbilityController, NetworkService
- **Target:** 80%+ reduction in ability request packets
- **Depends on:** #189, #206

#### #210: Client-Side Prediction for Simple Actions
https://github.com/JoshuaKushnir/Nightfall/issues/210

- Predict blocking, hit-react animations, posture bar easing locally
- Server sends authoritative updates; client smoothly reconciles
- Handle mispredictions gracefully
- Files: CombatController, PostureBar.lua
- **Target:** <1 frame input-to-response latency
- **Depends on:** #206

---

## Phase 5: Client UI & Animation (Parallel with Phase 4)

**Status:** Can Start Now (some depend on Phase 1)  
**Estimated Duration:** 2 weeks

### Sub-Issues

#### #211: UI Binding Optimization
https://github.com/JoshuaKushnir/Nightfall/issues/211

- Ensure bindings are O(1) lookups with no allocations
- Move expensive logic to batch update queue
- Cache frequently accessed values
- Files: `src/client/ui/**/*.lua`, UIBindingService
- **Target:** <0.1ms lambda execution time
- **Depends on:** #206

#### #212: UI Instance Recycling
https://github.com/JoshuaKushnir/Nightfall/issues/212

- Create UIRecycler service for common UI elements
- Pool damage numbers, tooltips, frames
- Ensure state cleanup between reuses
- Files: UIRecycler (new), DamageNumber, Tooltip
- **Target:** 80%+ reduction in UI instance creation/destruction
- **Depends on:** #211

#### #213: Animation Preloading & Asset Validation
https://github.com/JoshuaKushnir/Nightfall/issues/213

- Call AnimationLoader.PreloadAll on character spawn
- Audit all animation assets for rbxassetid0 stubs
- Replace stubs with real asset IDs
- Files: AnimationLoader, CharacterController, ability modules
- **Target:** <500ms total animation preload time

#### #214: HUD Update Queue & Batching
https://github.com/JoshuaKushnir/Nightfall/issues/214

- Implement HUDUpdateQueue service
- Consolidate property updates into batch sends
- Use HUDTheme for styling; HUDLayout for positioning
- Files: HUDUpdateQueue (new), HUDLayout, HUDTheme, UI modules
- **Target:** Batch 80%+ of HUD updates per frame
- **Depends on:** #211

---

## Commit Convention

**All commits must reference the sub-issue number:**

```
git commit -m "#189: Refactor service requires in ability modules

- Moved CombatService, DummyService, PostureService requires to module scope
- Removed per-hit pcall(require(...)) in OnHit, OnActivate callbacks
- Profiled: 15% reduction in combat loop frame time
- No gameplay changes; backward compatible
"
```

**Format:** `#{issue_number}: {brief description}`

---

## Progress Tracking

### How to Update Issues
1. Move issue to "In Progress" when starting work
2. Comment with profiling baseline before changes
3. Update PR/commits with `Closes #XXX` or manual linking
4. Comment with profiling results after changes
5. Close issue with summary of improvements

### Dashboard View
Track progress at: https://github.com/JoshuaKushnir/Nightfall/projects

Recommended filters:
- By phase: label:phase1, label:phase2, etc.
- By status: is:open, is:closed
- By priority: label:high, label:medium

---

## Key Dependencies

```
Phase 1 (No blockers)
  ├─ #189 → BLOCKS: #190, #191, #195, #196, #199, #206, #209
  ├─ #190 → BLOCKS: #191, #198, #199
  ├─ #191 → DEPENDS: #189, #190
  ├─ #192 → BLOCKS: #197, #198
  ├─ #193 → BLOCKS: #208
  └─ #194

Phase 2 (DEPENDS: Phase 1)
  ├─ #195 → BLOCKS: #196
  ├─ #196 → DEPENDS: #189, #195
  ├─ #197 → DEPENDS: #192
  ├─ #198 → DEPENDS: #190, #192
  └─ #199 → DEPENDS: #189, #190

Phase 3 (No dependencies)
  ├─ #200 → BLOCKS: #201, #205
  ├─ #201 → DEPENDS: #200
  ├─ #202
  ├─ #203 → BLOCKS: #204, #205
  ├─ #204 → DEPENDS: #203
  └─ #205 → DEPENDS: #200-204

Phase 4 (DEPENDS: Phase 1)
  ├─ #206 → BLOCKS: #207, #208, #209, #210
  ├─ #207 → DEPENDS: #206
  ├─ #208 → DEPENDS: #193, #206
  ├─ #209 → DEPENDS: #189, #206
  └─ #210 → DEPENDS: #206

Phase 5 (Mixed: #213 independent, #211 & #214 depend on #206)
  ├─ #211 → BLOCKS: #212, #214 (DEPENDS: #206)
  ├─ #212 → DEPENDS: #211
  ├─ #213 (Independent)
  └─ #214 → DEPENDS: #211
```

---

## Recommended Start Order

### Week 1-2 (Phase 1 - Foundation)
1. Start #189 (Service requires) - 3 days
2. Start #190 (Attribute caching) - 3 days
3. Start #191 (Tick loops) - 2 days
4. Start #192 (Movement caching) - 2 days
5. Start #193 (Debug gating) - 1 day
6. Start #194 (Module audit) - 1 day

### Week 3 (After Phase 1 Completes)
- Parallelize Phase 2, Phase 3, and Phase 4 prep
- Start #195-199 (Combat/Hitbox)
- Continue/finish #200-205 (VFX)
- Prepare #206-210 (Network)

### Week 4-6
- Complete Phase 2 & 3
- Roll out Phase 4
- Complete Phase 5

---

## Documentation

- **Full Epic Details:** `docs/OPTIMIZATION-EPIC.md`
- **Session Log:** `docs/session-log.md` (Session NF-093)
- **Rendering Report:** `docs/RENDERING-OPTIMIZATION-REPORT.md` (created by #205)

---

## Questions?

Review the epic issue for complete context: https://github.com/JoshuaKushnir/Nightfall/issues/188

Each sub-issue has detailed requirements, files to touch, and acceptance criteria in its GitHub description.