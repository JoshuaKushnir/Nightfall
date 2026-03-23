# 🚀 Optimization Epic – Quick Links

**Main Epic:** [#188 – Comprehensive Server & Client Performance Optimization](https://github.com/JoshuaKushnir/Nightfall/issues/188)

---

## Phase 1: Server & Code Optimizations (Foundation)
*Start here. No dependencies. Can all run in parallel.*

| Issue | Title | Priority |
|-------|-------|----------|
| [#189](https://github.com/JoshuaKushnir/Nightfall/issues/189) | Service Require Refactoring – Eliminate Per-Hit `pcall(require(...))` | 🔴 High |
| [#190](https://github.com/JoshuaKushnir/Nightfall/issues/190) | Attribute Caching in Tight Loops (Burning, CinderField, Grey Veil) | 🔴 High |
| [#191](https://github.com/JoshuaKushnir/Nightfall/issues/191) | Centralized Tick Loop for Periodic Effects | 🔴 High |
| [#192](https://github.com/JoshuaKushnir/Nightfall/issues/192) | Cache Movement Config & State Machine Optimization | 🔴 High |
| [#193](https://github.com/JoshuaKushnir/Nightfall/issues/193) | Disable Debug Systems in Production | 🟡 Medium |
| [#194](https://github.com/JoshuaKushnir/Nightfall/issues/194) | Module Initialization & Require Order Audit | 🟡 Medium |

---

## Phase 2: Hitbox, Combat & Movement
*Depends on Phase 1. Can parallelize with Phase 3.*

| Issue | Title | Priority | Blocks |
|-------|-------|----------|--------|
| [#195](https://github.com/JoshuaKushnir/Nightfall/issues/195) | Hitbox Lifetime & Size Tuning | 🔴 High | #196 |
| [#196](https://github.com/JoshuaKushnir/Nightfall/issues/196) | Batch Hitbox Checks for Training Dummies & PvE | 🔴 High | — |
| [#197](https://github.com/JoshuaKushnir/Nightfall/issues/197) | Movement State Machine Optimization | 🔴 High | — |
| [#198](https://github.com/JoshuaKushnir/Nightfall/issues/198) | Posture & Stamina/Breath Caching | 🔴 High | — |
| [#199](https://github.com/JoshuaKushnir/Nightfall/issues/199) | CombatService Per-Hit Optimization | 🔴 High | — |

---

## Phase 3: VFX, Models & Map
*Independent. Can start immediately. Lower risk than other phases.*

| Issue | Title | Priority | Blocks |
|-------|-------|----------|--------|
| [#200](https://github.com/JoshuaKushnir/Nightfall/issues/200) | Convert Design-Only VFX to Minimal Cheap Effects | 🟡 Medium | #201, #205 |
| [#201](https://github.com/JoshuaKushnir/Nightfall/issues/201) | Particle Emitter Reuse Pool | 🔴 High | #205 |
| [#202](https://github.com/JoshuaKushnir/Nightfall/issues/202) | Distance-Based Ambient Effect Culling | 🟡 Medium | #205 |
| [#203](https://github.com/JoshuaKushnir/Nightfall/issues/203) | Model Polygon Count & LOD Optimization | 🟡 Medium | #204, #205 |
| [#204](https://github.com/JoshuaKushnir/Nightfall/issues/204) | Remove Invisible & Overlapping Parts | 🟢 Low | #205 |
| [#205](https://github.com/JoshuaKushnir/Nightfall/issues/205) | Rendering Cost Profiling & Optimization Report | 🟡 Medium | — |

---

## Phase 4: Network & Replication
*Depends on Phase 1. Most complex; needs careful testing.*

| Issue | Title | Priority | Blocks |
|-------|-------|----------|--------|
| [#206](https://github.com/JoshuaKushnir/Nightfall/issues/206) | Event-Level Snapshot Architecture | 🔴 High | #207, #209, #210, #211 |
| [#207](https://github.com/JoshuaKushnir/Nightfall/issues/207) | Data Quantization for Network Compression | 🔴 High | — |
| [#208](https://github.com/JoshuaKushnir/Nightfall/issues/208) | Rate-Limited Logging & Debug Events | 🟡 Medium | — |
| [#209](https://github.com/JoshuaKushnir/Nightfall/issues/209) | Ability Activation Consolidation | 🔴 High | — |
| [#210](https://github.com/JoshuaKushnir/Nightfall/issues/210) | Client-Side Prediction for Simple Actions | 🔴 High | — |

---

## Phase 5: Client UI & Animation
*Mixed dependencies. #213 independent; #211/214 depend on Phase 4 start.*

| Issue | Title | Priority | Blocks |
|-------|-------|----------|--------|
| [#211](https://github.com/JoshuaKushnir/Nightfall/issues/211) | UI Binding Optimization | 🔴 High | #212, #214 |
| [#212](https://github.com/JoshuaKushnir/Nightfall/issues/212) | UI Instance Recycling | 🔴 High | — |
| [#213](https://github.com/JoshuaKushnir/Nightfall/issues/213) | Animation Preloading & Asset Validation | 🔴 High | — |
| [#214](https://github.com/JoshuaKushnir/Nightfall/issues/214) | HUD Update Queue & Batching | 🟡 Medium | — |

---

## 📊 Summary

| Phase | Issues | Count | Start When | Status |
|-------|--------|-------|-----------|--------|
| **Phase 1** | #189-194 | 6 | Now | Ready |
| **Phase 2** | #195-199 | 5 | After Phase 1 | Blocked |
| **Phase 3** | #200-205 | 6 | Now | Ready |
| **Phase 4** | #206-210 | 5 | After Phase 1 | Blocked |
| **Phase 5** | #211-214 | 4 | After Phase 4 ready | Partially Ready |
| **Total** | **188-214** | **26** | **TBD** | **Planning** |

---

## 🎯 Success Metrics

- ✅ Server frame time: 30%+ reduction (target <5ms for 100 players)
- ✅ Per-hit execution: <0.5ms (from ~2-3ms)
- ✅ Network bandwidth: 40%+ reduction
- ✅ Client FPS: 60+ on target devices
- ✅ GC spikes: <16ms
- ✅ Memory peak: 15%+ reduction

---

## 📝 How to Work on Issues

1. **Pick an issue** from the table above
2. **Click the link** to view full details (acceptance criteria, files to touch, etc.)
3. **Assign yourself** and move to "In Progress"
4. **Create a branch:** `git checkout -b feature/optimization-#XXX`
5. **Commit with issue reference:** `git commit -m "#XXX: Description of changes"`
6. **Profile before & after** (baseline measurements required)
7. **Submit PR** linking the issue
8. **Close issue** with summary of improvements

---

## 📚 Documentation

- **Full Epic Details:** [`docs/OPTIMIZATION-EPIC.md`](./docs/OPTIMIZATION-EPIC.md)
- **GitHub Issue Summary:** [`docs/OPTIMIZATION-GITHUB-SUMMARY.md`](./docs/OPTIMIZATION-GITHUB-SUMMARY.md)
- **Session Log:** [`docs/session-log.md`](./docs/session-log.md) (Session NF-093)

---

## 🚀 Recommended Workflow

### Week 1-2: Phase 1 Foundation
Start all 6 Phase 1 issues (#189-194) immediately. They have no interdependencies.

**Suggested assignees:**
- Engineer A: #189 (service requires) + #190 (attribute caching)
- Engineer B: #191 (tick loops) + #192 (movement caching)
- Engineer C: #193 (debug gating) + #194 (module init audit)

### Week 3: Parallelize Phases
- **Phase 2 team** (after Phase 1 done): #195-199
- **Phase 3 team** (independent): #200-205
- **Phase 4 prep** (after Phase 1 done): #206-210

### Week 4+: Complete & Rollout
- Finish all phases
- Regression testing
- Production rollout

---

**Created:** 2026-01-21  
**Last Updated:** 2026-01-21  
**Status:** All 26 issues created in GitHub