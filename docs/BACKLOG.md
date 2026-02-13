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

### 🔄 Phase 1: Core Framework (Infrastructure)
**Goal:** Establish the foundational systems required for all gameplay features.  
**Status:** In Planning  
**Issues:** [Filter by phase-1](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-1)

| Issue | Title | Labels | Status |
|-------|-------|--------|--------|
| [#24](https://github.com/JoshuaKushnir/Nightfall/issues/24) | ProfileService Data Wrapper | `critical`, `infrastructure`, `data` | ⏳ Pending |
| [#25](https://github.com/JoshuaKushnir/Nightfall/issues/25) | Enhanced State Machine System | `high`, `infrastructure`, `state-machine` | ⏳ Pending |
| [#26](https://github.com/JoshuaKushnir/Nightfall/issues/26) | Network Provider (Centralized RemoteEvent Handling) | `critical`, `infrastructure`, `networking` | ⏳ Pending |
| [#27](https://github.com/JoshuaKushnir/Nightfall/issues/27) | Server & Client Bootstrap Systems | `high`, `infrastructure`, `initialization` | ⏳ Pending |

**Key Dependencies:**
- #24 (DataService) is foundational for all data persistence
- #26 (NetworkProvider) is required for client-server communication
- #27 (Bootstrap) depends on other services being ready

---

### ⏳ Phase 2: Combat & Fluidity (The Feel)
**Goal:** Create responsive, satisfying combat with hitboxes, animations, and timing-based mechanics.  
**Status:** Pending  
**Issues:** [Filter by phase-2](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-2)

| Issue | Title | Labels | Status |
|-------|-------|--------|--------|
| [#28](https://github.com/JoshuaKushnir/Nightfall/issues/28) | Modular Hitbox System | `critical`, `combat`, `hitbox` | ⏳ Pending |
| [#29](https://github.com/JoshuaKushnir/Nightfall/issues/29) | Action Controller (Animation & Feel) | `high`, `combat`, `animation` | ⏳ Pending |
| [#30](https://github.com/JoshuaKushnir/Nightfall/issues/30) | Parrying & Block Mechanics | `high`, `combat`, `mechanics` | ⏳ Pending |

**Key Dependencies:**
- Phase 2 requires Phase 1 completion (#26 NetworkProvider, StateService)
- #29 depends on #28 (HitboxService)
- #30 depends on #28, #29

---

### ⏳ Phase 3: The Mantra System (Magic)
**Goal:** Implement the modular magic system with elements, classes, and resource management.  
**Status:** Pending  
**Issues:** [Filter by phase-3](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-3)

| Issue | Title | Labels | Status |
|-------|-------|--------|--------|
| [#31](https://github.com/JoshuaKushnir/Nightfall/issues/31) | Dynamic Mantra Loader | `critical`, `mantras`, `magic` | ⏳ Pending |
| [#32](https://github.com/JoshuaKushnir/Nightfall/issues/32) | Multi-Element/Class Logic & Requirements | `high`, `mantras`, `progression` | ⏳ Pending |
| [#33](https://github.com/JoshuaKushnir/Nightfall/issues/33) | Global Cooldown & Mana (Posture) Management | `high`, `mantras`, `resources` | ⏳ Pending |

**Key Dependencies:**
- #31 (MantraLoader) is foundational for magic system
- #32 depends on #31, #24 (DataService)
- #33 depends on #31, StateService, #26 (NetworkProvider)

---

### ⏳ Phase 4: World & Narrative (The RPG)
**Goal:** Add progression, dialogue, and RPG systems that give the game depth and replayability.  
**Status:** Pending  
**Issues:** [Filter by phase-4](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-4)

| Issue | Title | Labels | Status |
|-------|-------|--------|--------|
| [#34](https://github.com/JoshuaKushnir/Nightfall/issues/34) | Branching Dialogue System | `high`, `narrative`, `dialogue` | ⏳ Pending |
| [#35](https://github.com/JoshuaKushnir/Nightfall/issues/35) | Progression & Leveling System | `critical`, `progression`, `rpg` | ⏳ Pending |
| [#36](https://github.com/JoshuaKushnir/Nightfall/issues/36) | Armor/Class Component System | `high`, `equipment`, `systems` | ⏳ Pending |

**Key Dependencies:**
- #34 depends on #24 (DataService), #26 (NetworkProvider)
- #35 depends on #24 (DataService), StateService, #32 (ClassService)
- #36 depends on #24, #35, #32

---

### ⏳ Phase 5: Polish & Deployment (The Launch)
**Goal:** Optimize, secure, and prepare the game for public release with analytics and fail-safes.  
**Status:** Pending  
**Issues:** [Filter by phase-5](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-5)

| Issue | Title | Labels | Status |
|-------|-------|--------|--------|
| [#37](https://github.com/JoshuaKushnir/Nightfall/issues/37) | DataStore Fail-Safes & Analytics | `critical`, `data`, `analytics` | ⏳ Pending |
| [#38](https://github.com/JoshuaKushnir/Nightfall/issues/38) | Performance Optimization & Memory Management | `critical`, `optimization`, `performance` | ⏳ Pending |
| [#39](https://github.com/JoshuaKushnir/Nightfall/issues/39) | UI/UX Responsive Framework | `high`, `ui`, `ux` | ⏳ Pending |
| [#18](https://github.com/JoshuaKushnir/Nightfall/issues/18) | Testing Framework & QA Procedures | `medium`, `testing`, `qa` | ⏳ Pending |
| [#40](https://github.com/JoshuaKushnir/Nightfall/issues/40) | Launch Preparation & Deployment | `critical`, `deployment`, `launch` | ⏳ Pending |

**Key Dependencies:**
- #37 enhances #24 (DataService)
- #38 requires all systems for optimization
- #39 depends on #26 (NetworkProvider) and all gameplay systems
- #18 depends on all systems for testing
- #40 depends on ALL previous issues (launch-ready)

---

## 🎯 MVP Definition
**Minimum Viable Product includes:**
- ✅ Player data persistence (ProfileService) - [Issue #24](https://github.com/JoshuaKushnir/Nightfall/issues/24)
- ✅ Basic combat (hitboxes, animations, parrying) - [Issues #28-30](https://github.com/JoshuaKushnir/Nightfall/issues?q=is%3Aissue+label%3Aphase-2)
- ✅ 5-10 starter mantras (magic spells) - [Issue #31](https://github.com/JoshuaKushnir/Nightfall/issues/31)
- ✅ Character progression (leveling, stat allocation) - [Issue #35](https://github.com/JoshuaKushnir/Nightfall/issues/35)
- ✅ Simple equipment system (3-5 armor sets) - [Issue #36](https://github.com/JoshuaKushnir/Nightfall/issues/36)
- ✅ Basic dialogue with 1-2 NPCs - [Issue #34](https://github.com/JoshuaKushnir/Nightfall/issues/34)
- ✅ Polished UI and responsive feel - [Issue #39](https://github.com/JoshuaKushnir/Nightfall/issues/39)
- ✅ Performance optimization (60 FPS target) - [Issue #38](https://github.com/JoshuaKushnir/Nightfall/issues/38)
- ✅ Stable DataStore with fail-safes - [Issue #37](https://github.com/JoshuaKushnir/Nightfall/issues/37)

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