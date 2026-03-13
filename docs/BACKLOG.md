**Project:** Nightfall/Nightbound - Dark Fantasy Roblox RPG  
**Architecture:** Rojo + Luau (Strict Typing, DRY, Modular)  
**Goal:** Published MVP with Combat, Magic (Mantras), and Narrative Systems

---

## 🎯 Quick Links
- **[GitHub Issue Board](https://github.com/JoshuaKushnir/Nightfall/issues)** - All active issues and tasks
- **[Project Milestones](https://github.com/JoshuaKushnir/Nightfall/milestones)** - Phase tracking
- **[Session Log](session-log.md)** - Development history and technical memory
- **[Copilot Instructions](../.vscode/copilot-instructions.md)** or **[Copilot Instructions](.github/copilot-instructions.md)** - Engineering standards

---

## 📋 Development Approach
All development work is tracked through **GitHub Issues** with a structured label system:

**Phase Labels:**
- `phase-1` 🟢 Core Framework (Infrastructure)
- `phase-2` 🔵 Combat & Fluidity (The Feel)
- `phase-3` 🟣 Magic System (Mantras)
- `phase-4` 🔴 World & Narrative (The RPG)
- `phase-5` 🔥 Polish & Deployment (The Launch)

**Priority Labels:**
- `critical` - Blocks other work, must be done first
- `high` - Important for phase completion
- `medium` - Enhances functionality, not blocking
- `low` - Nice to have, cosmetic

**Type Labels:**
- `infrastructure`, `data`, `combat`, `magic`, `ui`, `networking`, `testing`, etc.

---

## 📊 Milestone Refactoring: Backend + Frontend Balance

To ensure features are actuated immediately as backend systems are built, each milestone now includes paired frontend and backend work:

| Phase | Before | After | Goal |
|-------|--------|-------|------|
| Phase 1 | 4 Backend | 4 Backend + 1 Frontend | Infrastructure + UI binding |
| Phase 2 | 2 Backend + 1 Frontend | 2 Backend + 2 Frontend | Hitboxes + Animations + Feedback |
| Phase 3 | 3 Backend | 3 Backend + 2 Frontend | Mantras + Casting UI + VFX |
| Phase 4 | 2 Backend + 1 Frontend | 2 Backend + 3 Frontend | RPG systems + Full UI suite |
| Phase 5 | 3 Backend + 2 Frontend | 3 Backend + 1 Frontend + 2 Full-Stack | Polish + Deployment |

---

## 📊 Progress Tracking

### ✅ Phase 0: Genesis (COMPLETE)
**Status:** Complete (Sessions NF-001 through NF-004)  
**Completed:**
- Repository structure with Rojo configuration
- StateService - The Nexus for player state management
- PlayerData types with strict typing
- Git repository initialized and committed
- Complete development roadmap
- Enhanced Copilot Instructions with engineering manifesto
- GitHub Issue Board & Label System with 32+ labels
- All issues migrated to GitHub with proper labels and linked dependencies
- **GitHub is now the single source of truth for all issues**
- Completed: February 12, 2026

---

### ✅ Phase 1: Core Framework (Infrastructure)
**Epic:** Infrastructure foundation  
**Goal:** Establish the foundational systems required for all gameplay features.  
**Status:** ✅ COMPLETE (February 12, 2026)  
**Completed Features:**
- Backend Foundation: DataService (ProfileService wrapper), NetworkService (rate limiting, validation), StateService (state machine with validation)
- Bootstrap Systems: Server and client runtime initialization with dependency injection
- Frontend Framework: StateSyncController + UIBinding reactive system + PlayerHUD demo
- Full Stack: Client-server state synchronization with network event system

---

### ✅ Phase 2: Combat & Fluidity (The Feel)
**Epic:** Combat system implementation  
**Goal:** Implement hitboxes, damage calculation, and visual feedback for responsive combat.  
**Status:** ✅ COMPLETE (February 13, 2026)  
**Completed Features:**
- HitboxService: Box/Sphere/Raycast collision detection
- ActionController: Input bindings and hitbox creation
- CombatFeedbackUI: Floating damage numbers and visual feedback
- DefenseService: Block/Parry mechanics
- CombatService: Server-authoritative hit validation with damage variance, critical hits, rate limiting
- Complete client-server combat loop with async validation

---

### ✅ Phase 2: Combat & Fluidity (The Feel)
**Epic:** [Issue #49](https://github.com/JoshuaKushnir/Nightfall/issues/49)  
**Goal:** Create responsive, satisfying combat with hitboxes, animations, and timing-based mechanics paired with visual feedback.  
**Status:** ✅ COMPLETE (February 13, 2026)  
**Issues:** [Filter by phase-2](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-2)

| Issue | Title | Type | Labels | Status |
|-------|-------|------|--------|--------|
| [#28](https://github.com/JoshuaKushnir/Nightfall/issues/28) | Modular Hitbox System | `backend` | `critical`, `combat`, `hitbox`, `backend` | ✅ Complete |
| [#29](https://github.com/JoshuaKushnir/Nightfall/issues/29) | Action Controller (Animation & Feel) | `frontend` | `high`, `combat`, `animation`, `client`, `frontend` | ✅ Complete |
| [#30](https://github.com/JoshuaKushnir/Nightfall/issues/30) | Parrying & Block Mechanics | `backend` | `high`, `combat`, `mechanics`, `backend` | ✅ Complete |
| [#43](https://github.com/JoshuaKushnir/Nightfall/issues/43) | Combat Feedback UI (Health Bar, Damage Numbers, VFX) | `frontend` | `high`, `combat`, `ui`, `visual-feedback`, `frontend` | ✅ Complete |

**Session:** NF-009

**Completed Implementation:**
- **Client Layer:** Input system, action queueing, hitbox creation timing, camera effects
- **Server Layer:** Hit validation, damage calculation, rate limiting, defense integration
- **Feedback Layer:** Floating damage numbers, block/parry visual effects, network-synced
- **Full Pipeline:** Click → Hitbox → Server Validation → Damage → UI Feedback

**Key Systems:**
- ✅ Utils.lua - Geometry collision and validation utilities
- ✅ HitboxService - Box/Sphere/Raycast collision detection
- ✅ ActionController - Input bindings and action execution
- ✅ CombatService - Server-authoritative hit validation and damage
- ✅ CombatFeedbackUI - Floating damage numbers and visual effects
- ✅ DefenseService - Block (50% reduction) and Parry (0.2s window) mechanics
- ✅ Complete NetworkTypes for all combat events

**What's Enabled:**
- Left-click: Light Attack (0.6s duration, 0.3 hit frame, 0.1s hit-stop)
- Right-click: Heavy Attack (1.2s duration, 0.5 hit frame, 0.15s hit-stop)
- Q: Dodge roll (0.5s, iframes)
- Shift: Parry counter (0.3s window, stuns attacker 0.5s)
- Right-mouse-hold: Block (reduces 50% damage, drains posture)

---

### ✅ Phase 2: Smooth Movement System (Epic #56)
**Epic:** [Issue #56](https://github.com/JoshuaKushnir/Nightfall/issues/56)  
**Goal:** Deepwoken-style weighty movement with acceleration, coyote time, jump buffer, sprint.  
**Status:** Implemented (February 14, 2026)

| Sub-issue | Title | Status |
|-----------|-------|--------|
| [#57](https://github.com/JoshuaKushnir/Nightfall/issues/57) | Coyote time and jump buffer | ✅ |
| [#58](https://github.com/JoshuaKushnir/Nightfall/issues/58) | MovementController: acceleration, walk/run | ✅ |
| [#59](https://github.com/JoshuaKushnir/Nightfall/issues/59) | StateService integration and combat state respect | ✅ |
| [#60](https://github.com/JoshuaKushnir/Nightfall/issues/60) | Sprint and optional slope handling | ✅ |

**Implementation:** `MovementController.lua` – smoothed WalkSpeed, coyote time (0.12s), jump buffer (0.15s), sprint (LeftShift), combat-state respect via StateSyncController.

---

### ⏳ Phase 3: The Mantra System (Magic)
**Epic:** Magic system implementation  
**Goal:** Implement the modular magic system with elements, classes, and resource management paired with casting UI and visual feedback.  
**Status:** Pending  
**Planned Features:**
- Dynamic Mantra Loader for modular spell system
- Multi-Element/Class Logic & Requirements
- Global Cooldown & Mana (Posture) Management
- Mantra Casting UI & Keybind System
- Mantra VFX & Animation System

---

### ⏳ Phase 4: World & Narrative (The RPG)
**Epic:** RPG systems implementation  
**Goal:** Add progression, dialogue, and RPG systems that give the game depth and replayability, with full UI integration.  
**Status:** Pending  
**Planned Features:**
- Branching Dialogue System
- Progression & Leveling System
- Armor/Class Component System
- Character Sheet & Stat Display UI
- Equipment Inventory & Loadout UI

---

### ⏳ Phase 5: Polish & Deployment (The Launch)
**Epic:** Final polish and launch preparation  
**Goal:** Optimize, secure, and prepare the game for public release with analytics and fail-safes.  
**Status:** Pending  
**Planned Features:**
- DataStore Fail-Safes & Analytics
- Performance Optimization & Memory Management
- UI/UX Responsive Framework
- Testing Framework & QA Procedures
- Launch Preparation & Deployment

---
- All Phase 5 issues depend on Phases 1-4 being complete or substantially complete

---

## 🎯 MVP Definition — Accurate Status (Updated March 2026)

> **Last full re-evaluation:** Session NF-070, March 12 2026

---

### ✅ DONE — Do not touch

| # | System | Notes |
|---|--------|-------|
| 1 | Core infrastructure (DataService, StateService, NetworkService, Bootstrap) | Phase 1 complete |
| 2 | Combat loop (hitboxes, CombatService, parry/block, damage numbers) | Phase 2 complete |
| 3 | Aspect types, registry, switching, cooldowns, mana regen | Phase 3 complete |
| 4 | Inventory system (InventoryService, InventoryController — Deepwoken layout) | #151 + #62 complete |
| 5 | Stat allocation (Strength, Fortitude, Intelligence, etc. — P-key panel) | NF-042/NF-043 complete |
| 6 | Resonance & Ring soft caps, shard loss on death | NF-041 complete |
| 7 | Movement (sprint, dash, lunge, wall-run, ledge catch, vault, slide + collision fixes) | NF-034 + NF-061/062 complete |
| 8 | CI/CD pipeline (test runner, poll_task.py, GitHub Actions) | Infrastructure session complete |

---

### 🔴 CRITICAL — Blocking. Nothing fun works without these.

| Priority | System | What's Missing | Issue | Scope |
|----------|--------|----------------|-------|-------|
| 1 | **Depth-1 Ember abilities** | Every Aspect ability is a stub. No cast produces real effects. Core gameplay loop — without it the game is a running simulator. | [#174](https://github.com/JoshuaKushnir/Nightfall/issues/174) | 1 session per Aspect; Ember first |
| 2 | **Basic enemy AI** | Dummy mobs are passive. No PvE target = no resonance loop, nothing to kill. Even one NPC that walks toward you and swings unlocks the feedback loop. | [#175](https://github.com/JoshuaKushnir/Nightfall/issues/175) | Medium — NPC state machine |
| 3 | **HUD resonance display** | Players cannot see their core progression currency. Stat panel (P-key) exists but HUD doesn't subscribe to resonance listeners. | [#176](https://github.com/JoshuaKushnir/Nightfall/issues/176) | Small — 1 session |
| 4 | **Zone / ring trigger system** | `ProgressionService.SetPlayerRing` has no caller. Ring gating, luminance drain, and soft caps are all dead code. | [#176](https://github.com/JoshuaKushnir/Nightfall/issues/176) | Medium — bundled with HUD |

---

### 🟡 HIGH — Needed for a complete MVP

| Priority | System | What's Missing | Scope |
|----------|--------|----------------|-------|
| 5 | Remaining Depth-1 abilities (Ash, Tide, Gale, Void) | Once Ember pattern established, all four follow the same template. | 1 session each |
| 6 | **Branching Dialogue System** | NetworkTypes has DialogueStart/Choice/QuestAccept/QuestComplete defined. DialogueService + DialogueController don't exist. | [#177](https://github.com/JoshuaKushnir/Nightfall/issues/177) — Phase 4 kickoff |
| 7 | **Equipment / Armor System** | InventoryService can hold armor items. ArmorService that applies stat modifiers doesn't exist. | Medium |
| 8 | **Character sheet UI** | P-key stat panel exists. Full character sheet (equipped armor, aspect, discipline, stat totals) doesn't. | Small |

---

### 🟢 MEDIUM — Polish that matters for launch

| Priority | System | Notes |
|----------|--------|-------|
| 9 | Omen system | Five thresholds, passive corruptions, visible to others. Designed, not built. |
| 10 | Luminance drain in deep zones | Ring 4+ mechanic. Depends on zone triggers (#176). |
| 11 | The Between (death respawn experience) | 30-second between-state, ally revive, Ember Point system. Designed, not built. |
| 12 | VFX/Animations on abilities | Everything is stubs. Even simple particles would dramatically change perceived quality. |
| 13 | DataStore fail-safes | ProfileService wrapper exists; exponential backoff + graceful shutdown are mocked, not hardened. |

---

### 🔵 POST-MVP — Do not build yet

- Guild/clan system
- World bosses / Convergences
- Crafting and economy
- Seasonal events
- Ring 5 (The Null)
- The Ashen Record (account-wide meta progression)
- Advanced PvP arenas / Dueling Grounds

---

### 🗓️ The Next 4 Sessions (Optimal Sequencing)

| Session | Issue | Scope |
|---------|-------|-------|
| Session 1 | [#174](https://github.com/JoshuaKushnir/Nightfall/issues/174) — Depth-1 Ember abilities | Real hitbox + damage + VFX stub |
| Session 2 | [#175](https://github.com/JoshuaKushnir/Nightfall/issues/175) — Basic enemy AI | One NPC type: aggro + pathfind + swing |
| Session 3 | [#176](https://github.com/JoshuaKushnir/Nightfall/issues/176) — HUD resonance + zone triggers | Small, bundled |
| Session 4 | [#177](https://github.com/JoshuaKushnir/Nightfall/issues/177) — DialogueService + Controller | Phase 4 kickoff |

---

## 🔧 Development Workflow

### Before Starting Work:
1. **Check GitHub Issues** - [View all issues](https://github.com/JoshuaKushnir/Nightfall/issues)
2. **Read [session-log.md](session-log.md)** - Understand current context
3. **Review [copilot-instructions.md](../.vscode/copilot-instructions.md)** - Follow engineering standards
4. **Assign yourself** to the issue you're working on
5. **Update issue status** - Move to "In Progress"

### During Development:
1. **Log progress** in [session-log.md](session-log.md)
2. **Reference issue numbers** in commits and comments
3. **Follow type safety** and architectural patterns
4. **Test thoroughly** before marking complete

### After Completing Work:
1. **Update [session-log.md](session-log.md)** with completed work
2. **Close the GitHub issue** with completion notes
3. **Link related issues** if follow-up work is needed
4. **Commit with proper message** format: `feat(#XX): Description`

---

## 📊 Issue Board Organization

### Milestones
Create GitHub Milestones for each phase:
- **Phase 1: Core Framework** - Target: March 2026
- **Phase 2: Combat System** - Target: April 2026
- **Phase 3: Magic System** - Target: May 2026
- **Phase 4: RPG Systems** - Target: June 2026
- **Phase 5: Launch Ready** - Target: July 2026

### Projects
Use GitHub Projects for kanban-style tracking:
- **Nightfall Development** board with columns:
  - 📋 Backlog
  - 🔄 In Progress
  - 👀 In Review
  - ✅ Complete
  - 🔥 Blocked

### Issue Templates
Standardize issue creation with templates:
- **Feature Request** - New gameplay feature
- **Bug Report** - Issues and fixes
- **Technical Debt** - Refactoring and optimization
- **Documentation** - Docs and guides

---

## 📚 Additional Resources

### Technical Documentation
- [Engineering Manifesto](../.vscode/copilot-instructions.md) - Complete engineering standards
- [Session Log](session-log.md) - Development history and technical memory
- [PlayerData Types](../src/shared/types/PlayerData.lua) - Core data structures
- [StateService](../src/shared/modules/StateService.lua) - State machine implementation

### External Dependencies
- **ProfileService** - Data persistence (GitHub: MadStudioRoblox/ProfileService)
- **TestEZ** - Unit testing framework (GitHub: Roblox/testez)
- **Rojo** - Filesystem sync (GitHub: rojo-rbx/rojo)

### Version Control
- **Commit Format:** `<type>(#issue): Description`
- **Branch Strategy:** `main` for stable, `develop` for integration, `feature/issue-XX` for work
- **Tag Releases:** `v0.1.0-alpha`, `v1.0.0` (MVP launch)

---

## ⚠️ Important Notes

### GitHub is the Source of Truth
- **All issues are tracked in GitHub** - This document is a roadmap/overview only
- **Check GitHub for latest status** - Issues may be updated, closed, or modified
- **Use GitHub Projects** for visual kanban board
- **Reference issues in all work** - Commits, PRs, session-log entries

### Maintaining This Document
- Update this roadmap when **phases change** or **major milestones** are reached
- Keep **phase summaries** updated with actual completion dates
- Link to **GitHub issues** for detailed specifications
- This is a **high-level overview**, not detailed specs

---

**Last Updated:** February 12, 2026 (Session NF-004 - GitHub Issue Board Migration)  
**GitHub Repository:** [JoshuaKushnir/Nightfall](https://github.com/JoshuaKushnir/Nightfall)  
**Issue Board:** [View All Issues](https://github.com/JoshuaKushnir/Nightfall/issues)