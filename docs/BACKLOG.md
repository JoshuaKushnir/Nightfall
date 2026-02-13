# Nightfall: Development Roadmap
**Project:** Nightfall/Nightbound - Dark Fantasy Roblox RPG  
**Architecture:** Rojo + Luau (Strict Typing, DRY, Modular)  
**Goal:** Published MVP with Combat, Magic (Mantras), and Narrative Systems

---

## 🎯 Quick Links
- **[GitHub Issue Board](https://github.com/JoshuaKushnir/Nightfall/issues)** - All active issues and tasks
- **[Project Milestones](https://github.com/JoshuaKushnir/Nightfall/milestones)** - Phase tracking
- **[Session Log](session-log.md)** - Development history and technical memory
- **[Copilot Instructions](../.vscode/copilot-instructions.md)** - Engineering standards

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

**New Issues Added:** #41-#46 (Client-facing features that actuate backend systems)

---

## 📊 Progress Tracking

### ✅ Phase 0: Genesis (COMPLETE)
**Status:** Complete (Sessions NF-001, NF-002, NF-003, NF-004)  
**Completed:**
- Repository structure with Rojo configuration
- [StateService](../src/shared/modules/StateService.lua) - The Nexus for player state management
- [PlayerData](../src/shared/types/PlayerData.lua) types with strict typing
- Git repository initialized and committed
- Complete development roadmap with 19 issues
- **[Issue #1](https://github.com/JoshuaKushnir/Nightfall/issues/1): Enhanced Copilot Instructions** (NF-003)
  - 10x expansion of engineering manifesto (50 → 800+ lines)
  - Mandatory workflow protocols for issue board integration
  - Comprehensive architectural patterns and code standards
  - Testing, documentation, and security guidelines
- **GitHub Issue Board & Label System** (NF-004)
  - 32+ labels created (phase, priority, type)
  - 18 issues (#24-40, plus #18) migrated to GitHub
  - All issues have proper labels and dependencies documented
  - BACKLOG.md restructured to reference GitHub (974 → 260 lines)
  - **GitHub is now the single source of truth for all issues**
  - Completed: February 12, 2026

---

### ✅ Phase 1: Core Framework (Infrastructure)
**Epic:** [Issue #48](https://github.com/JoshuaKushnir/Nightfall/issues/48)  
**Goal:** Establish the foundational systems required for all gameplay features.  
**Status:** ✅ COMPLETE (February 12, 2026)  
**Issues:** [Filter by phase-1](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-1)

| Issue | Title | Type | Labels | Status |
|-------|-------|------|--------|--------|
| [#24](https://github.com/JoshuaKushnir/Nightfall/issues/24) | ProfileService Data Wrapper | `backend` | `critical`, `infrastructure`, `data`, `backend` | ✅ Complete |
| [#25](https://github.com/JoshuaKushnir/Nightfall/issues/25) | Enhanced State Machine System | `backend` | `high`, `infrastructure`, `state-machine`, `backend` | ✅ Complete |
| [#26](https://github.com/JoshuaKushnir/Nightfall/issues/26) | Network Provider (Centralized RemoteEvent Handling) | `backend` | `critical`, `infrastructure`, `networking`, `backend` | ✅ Complete |
| [#27](https://github.com/JoshuaKushnir/Nightfall/issues/27) | Server & Client Bootstrap Systems | `backend` | `high`, `infrastructure`, `initialization`, `backend` | ✅ Complete |
| [#42](https://github.com/JoshuaKushnir/Nightfall/issues/42) | Client-Side Binding Framework & State Sync UI | `frontend` | `high`, `infrastructure`, `ui`, `client`, `frontend` | ✅ Complete |

**Completed Features:**
- **Backend Foundation:** DataService (ProfileService wrapper) → NetworkService (rate limiting, validation) → StateService (state machine with validation)
- **Bootstrap Systems:** Server and client runtime initialization with dependency injection
- **Frontend Framework:** StateSyncController + UIBinding reactive system + PlayerHUD demo
- **Full Stack:** Client-server state synchronization with network event system

**Sessions:** NF-006, NF-007, NF-008

---

### 🔄 Phase 2: Combat & Fluidity (The Feel)
**Epic:** [Issue #49](https://github.com/JoshuaKushnir/Nightfall/issues/49)  
**Goal:** Create responsive, satisfying combat with hitboxes, animations, and timing-based mechanics paired with visual feedback.  
**Status:** Pending  
**Issues:** [Filter by phase-2](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-2)

| Issue | Title | Type | Labels | Status |
|-------|-------|------|--------|--------|
| [#28](https://github.com/JoshuaKushnir/Nightfall/issues/28) | Modular Hitbox System | `backend` | `critical`, `combat`, `hitbox`, `backend` | ⏳ Pending |
| [#29](https://github.com/JoshuaKushnir/Nightfall/issues/29) | Action Controller (Animation & Feel) | `frontend` | `high`, `combat`, `animation`, `client`, `frontend` | ⏳ Pending |
| [#30](https://github.com/JoshuaKushnir/Nightfall/issues/30) | Parrying & Block Mechanics | `backend` | `high`, `combat`, `mechanics`, `backend` | ⏳ Pending |
| [#43](https://github.com/JoshuaKushnir/Nightfall/issues/43) | Combat Feedback UI (Health Bar, Damage Numbers, VFX) | `frontend` | `high`, `combat`, `ui`, `visual-feedback`, `frontend` | ⏳ Pending |

**Key Dependencies:**
- **Parallel:** #28 (Hitbox Backend) ↔ #29 (Animation Frontend) - Build together for feel
- **Backend Flow:** #28 → #30 (Parry mechanics depend on hitbox detection)
- **Frontend Flow:** #29 → #43 (Feedback animates combat results)
- **Integration:** #43 displays results from #30 and #28

---

### ⏳ Phase 3: The Mantra System (Magic)
**Epic:** [Issue #50](https://github.com/JoshuaKushnir/Nightfall/issues/50)  
**Goal:** Implement the modular magic system with elements, classes, and resource management paired with casting UI and visual feedback.  
**Status:** Pending  
**Issues:** [Filter by phase-3](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-3)

| Issue | Title | Type | Labels | Status |
|-------|-------|------|--------|--------|
| [#31](https://github.com/JoshuaKushnir/Nightfall/issues/31) | Dynamic Mantra Loader | `backend` | `critical`, `mantras`, `magic`, `backend` | ⏳ Pending |
| [#32](https://github.com/JoshuaKushnir/Nightfall/issues/32) | Multi-Element/Class Logic & Requirements | `backend` | `high`, `mantras`, `progression`, `backend` | ⏳ Pending |
| [#33](https://github.com/JoshuaKushnir/Nightfall/issues/33) | Global Cooldown & Mana (Posture) Management | `backend` | `high`, `mantras`, `resources`, `backend` | ⏳ Pending |
| [#44](https://github.com/JoshuaKushnir/Nightfall/issues/44) | Mantra Casting UI & Keybind System | `frontend` | `high`, `mantras`, `ui`, `client`, `frontend` | ⏳ Pending |
| [#45](https://github.com/JoshuaKushnir/Nightfall/issues/45) | Mantra VFX & Animation System | `frontend` | `high`, `mantras`, `visual-feedback`, `animation`, `frontend` | ⏳ Pending |

**Key Dependencies:**
- **Backend Foundation:** #31 (MantraLoader) → #32 (Class Logic) + #33 (Resources)
- **Frontend Parallel:** #44 (Casting UI) waits on #31 ready, #45 (VFX) depends on #31 for spell data
- **Integration:** #44 triggers #33 (mana cost), #45 displays spell effects from #31
- Both #44 and #45 depend on Phase 1 completion (#26 NetworkProvider)

---

### ⏳ Phase 4: World & Narrative (The RPG)
**Epic:** [Issue #51](https://github.com/JoshuaKushnir/Nightfall/issues/51)  
**Goal:** Add progression, dialogue, and RPG systems that give the game depth and replayability, with full UI integration.  
**Status:** Pending  
**Issues:** [Filter by phase-4](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-4)

| Issue | Title | Type | Labels | Status |
|-------|-------|------|--------|--------|
| [#34](https://github.com/JoshuaKushnir/Nightfall/issues/34) | Branching Dialogue System | `frontend` | `high`, `narrative`, `dialogue`, `ui`, `frontend` | ⏳ Pending |
| [#35](https://github.com/JoshuaKushnir/Nightfall/issues/35) | Progression & Leveling System | `backend` | `critical`, `progression`, `rpg`, `backend` | ⏳ Pending |
| [#36](https://github.com/JoshuaKushnir/Nightfall/issues/36) | Armor/Class Component System | `backend` | `high`, `equipment`, `systems`, `backend` | ⏳ Pending |
| [#46](https://github.com/JoshuaKushnir/Nightfall/issues/46) | Character Sheet & Stat Display UI | `frontend` | `high`, `ui`, `progression`, `client`, `frontend` | ⏳ Pending |
| [#47](https://github.com/JoshuaKushnir/Nightfall/issues/47) | Equipment Inventory & Loadout UI | `frontend` | `high`, `ui`, `equipment`, `client`, `frontend` | ⏳ Pending |

**Key Dependencies:**
- **Backend Path:** #35 (Progression) → #36 (Equipment), both feed #46+#47
- **Frontend Path:** #34 (Dialogue) is independent; #46 displays #35 data; #47 displays #36 data
- #35 depends on #24 (DataService), StateService, #32 (ClassService)
- #36 depends on #24, #35, #32
- All frontend issues (#34, #46, #47) depend on #26 (NetworkProvider) for sync

---

### ⏳ Phase 5: Polish & Deployment (The Launch)
**Epic:** [Issue #18](https://github.com/JoshuaKushnir/Nightfall/issues/18)  
**Goal:** Optimize, secure, and prepare the game for public release with analytics and fail-safes.  
**Status:** Pending  
**Issues:** [Filter by phase-5](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-5)

| Issue | Title | Type | Labels | Status |
|-------|-------|------|--------|--------|
| [#37](https://github.com/JoshuaKushnir/Nightfall/issues/37) | DataStore Fail-Safes & Analytics | `backend` | `critical`, `data`, `analytics`, `backend` | ⏳ Pending |
| [#38](https://github.com/JoshuaKushnir/Nightfall/issues/38) | Performance Optimization & Memory Management | `full-stack` | `critical`, `optimization`, `performance`, `full-stack` | ⏳ Pending |
| [#39](https://github.com/JoshuaKushnir/Nightfall/issues/39) | UI/UX Responsive Framework | `frontend` | `high`, `ui`, `ux`, `client`, `frontend` | ⏳ Pending |
| [#18](https://github.com/JoshuaKushnir/Nightfall/issues/18) | Testing Framework & QA Procedures | `backend` | `medium`, `testing`, `qa`, `backend` | ⏳ Pending |
| [#40](https://github.com/JoshuaKushnir/Nightfall/issues/40) | Launch Preparation & Deployment | `full-stack` | `critical`, `deployment`, `launch`, `full-stack` | ⏳ Pending |

**Key Dependencies:**
- **Backend:** #37 enhances #24 (DataService), #18 creates test harness
- **Full-Stack:** #38 requires all systems for optimization, #40 requires ALL previous issues (launch-ready)
- **Frontend:** #39 polishes all UI created in Phases 1-4
- All Phase 5 issues depend on Phases 1-4 being complete or substantially complete

---

## 🎯 MVP Definition
**Minimum Viable Product includes:**

**Backend Systems:**
- ✅ Player data persistence (ProfileService) - [Issue #24](https://github.com/JoshuaKushnir/Nightfall/issues/24)
- ✅ State management & reactivity - [Issues #25, #26, #27](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-1)
- ✅ Basic combat logic (hitboxes, parrying) - [Issues #28, #30](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-2)
- ✅ 5-10 starter mantras with cooldown/mana - [Issues #31-33](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-3)
- ✅ Character progression (leveling, stat allocation) - [Issue #35](https://github.com/JoshuaKushnir/Nightfall/issues/35)
- ✅ Equipment system (3-5 armor sets) - [Issue #36](https://github.com/JoshuaKushnir/Nightfall/issues/36)

**Frontend/UI Systems:**
- ✅ Client state binding & data sync - [Issue #42](https://github.com/JoshuaKushnir/Nightfall/issues/42)
- ✅ Combat animations & visual feedback - [Issues #29, #43](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-2)
- ✅ Mantra casting UI & keybinds - [Issues #44-45](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-3)
- ✅ Character sheet (stats, progression display) - [Issue #46](https://github.com/JoshuaKushnir/Nightfall/issues/46)
- ✅ Equipment inventory & loadout UI - [Issue #47](https://github.com/JoshuaKushnir/Nightfall/issues/47)
- ✅ Dialogue UI with branching options - [Issue #34](https://github.com/JoshuaKushnir/Nightfall/issues/34)
- ✅ Responsive UI polish - [Issue #39](https://github.com/JoshuaKushnir/Nightfall/issues/39)

**Post-MVP (Future Updates):**
- Advanced PvP arenas
- Guild/clan system
- World bosses and raids
- Expanded narrative (quest chains)
- Crafting and economy
- Seasonal events

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