# Nightbound: Engineering Manifesto
**Project:** Nightbound — Dark Fantasy Roblox RPG  
**Stack:** Rojo + Luau (Strict Typing, Service/Controller, DRY)  
**Repo:** JoshuaKushnir/Nightfall  
**Last Updated:** February 2026

---

## ⚡ THE ONE RULE THAT OVERRIDES EVERYTHING

> **NO CODE WITHOUT AN ISSUE. NO ISSUE WITHOUT A COMMIT. NO COMMIT WITHOUT A PUSH.**

If you are about to write code and there is no GitHub issue for it, stop. Create the issue first. This is not a suggestion. It is the operating model.

---

## 🧠 SESSION START — DO THIS EVERY TIME, IN ORDER

Before touching any file or creating any issue:

```
1. READ docs/session-log.md               — what was built, last session ID, current state
2. READ .github/copilot-instructions.md   — this file
3. RUN: gh issue list --state open        — what is pending and in progress
4. IDENTIFY the next issue to work on     — highest priority, unblocked
5. ASSIGN yourself and move to In Progress on GitHub
```

Do not skip step 1. The session log is your memory. Without it you will duplicate work, break things that are already done, or build on wrong assumptions.

---

## 📋 SESSION END — DO THIS EVERY TIME, IN ORDER

After completing any meaningful unit of work:

```
1. COMMIT with issue reference
2. PUSH to remote
3. UPDATE the GitHub issue (progress comment or close it)
4. UPDATE docs/session-log.md
5. COMMIT the session log: docs(#XX): Update session log
6. PUSH again
```

Never end a session with uncommitted changes. Never end a session without updating the session log.

---

## 🗂️ ISSUE-FIRST DEVELOPMENT

### Creating Issues

Every piece of work — feature, bugfix, refactor, spec gap, tech debt — needs a GitHub issue before implementation begins. No exceptions.

```bash
gh issue create \
  --repo JoshuaKushnir/Nightfall \
  --title "verb + noun description" \
  --label "phase-X,priority,type" \
  --milestone "Phase X: Name" \
  --body "$(cat <<'EOF'
## Overview
[What this is and why it exists — 1-2 sentences]

## Acceptance Criteria
- [ ] [Concrete, testable, binary — either done or not]
- [ ] [Each criterion maps to something you can verify in Studio or via type checker]

## Dependencies
Blocked by: #XX

## Files Affected
- `src/path/to/file.lua` (create / modify)

## Notes
[Spec gaps, design decisions, placeholder values used]
EOF
)"
```

### Issue Labels

Always apply three label types:

| Category | Options |
|---|---|
| **Phase** | `phase-1` `phase-2` `phase-3` `phase-4` `phase-5` |
| **Priority** | `critical` `high` `medium` `low` |
| **Type** | `backend` `frontend` `infrastructure` `data` `combat` `magic` `ui` `networking` `tech-debt` `spec-gap` `bug` `epic` |

### Issue Lifecycle

```
Created → [assigned, In Progress] → [progress comments during work] → [all criteria met] → Closed
```

- Add a progress comment every time you complete a major step within an issue
- Never close an issue until ALL acceptance criteria are verified in Roblox Studio
- If you discover a bug while working on an issue: stop, create a new `bug` issue, reference it in the current issue, do not fix silently

### Epics and Sub-Issues

Each phase has one epic issue. All work for that phase is a sub-issue linked to the epic.

```bash
# Link a sub-issue to its parent epic
gh sub-issue add <epic-number> <sub-issue-number> --repo JoshuaKushnir/Nightfall

# Create a new sub-issue already linked
gh sub-issue create --parent <epic-number> --title "Title" --repo JoshuaKushnir/Nightfall
```

Epic IDs (verify against board):
- Phase 1 Core Framework: verify on board
- Phase 2 Combat & Fluidity: verify on board
- Phase 3 Aspect / Mantra: verify on board
- Phase 4 World & Narrative: verify on board
- Phase 5 Polish & Launch: #18

### Blocking Relationships

Hard dependencies must be set as blocking relationships on GitHub, not just mentioned in descriptions.

```
Use GitHub Web: Issue → "Linked issues" sidebar → "blocks" or "blocked by"
```

Rule: only set `blocks` when work **cannot start** without the other issue complete. Do not use it for soft preferences.

---

## 🏗️ ARCHITECTURE

### Folder Map

```
src/
  server/
    services/         ← all server logic (DataService, CombatService, AspectService...)
    runtime/          ← init.lua bootstrap — loads and starts all services
  client/
    controllers/      ← all client logic (ActionController, InventoryController...)
    modules/          ← client-only utilities (UIBinding, DebugInput...)
    runtime/          ← init.lua bootstrap — loads and starts all controllers
  shared/
    types/            ← ALL type definitions (PlayerData, NetworkTypes, AspectTypes...)
    modules/          ← shared logic (StateService, HitboxService, Utils, AspectRegistry...)
    network/          ← NetworkProvider — Remote registry
docs/
  session-log.md      ← THE MEMORY FILE
  BACKLOG.md          ← phase overview, links to GitHub
.github/
  copilot-instructions.md  ← this file
```

### The Hard Rules of Architecture

**1. No cross-boundary requires**
```lua
-- ✅ Correct
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

-- ❌ Never do this from server
local ActionController = require(game.StarterPlayerScripts.controllers.ActionController)
```

**2. StateService is the only way to change player state**
```lua
-- ✅ Correct
StateService:SetPlayerState(player, "Attacking")

-- ❌ Never do this
playerData.State = "Attacking"
```

**3. Server validates everything the client sends**
```lua
-- Every RemoteEvent handler on the server:
NetworkService:RegisterHandler("AbilityCastRequest", function(player, packet)
    -- 1. Validate player exists
    -- 2. Validate packet fields are present and correct type
    -- 3. Validate state allows this action
    -- 4. Validate resources (mana, cooldown)
    -- 5. Validate range/position
    -- Only then: execute
end)
```

**4. Utilities go in Utils**

If the same logic appears in two files, it moves to `src/shared/modules/Utils.lua`. No exceptions.

**5. Services use Init/Start pattern**
```lua
local MyService = {}
MyService._initialized = false

function MyService:Init(dependencies)
    self._dep = dependencies.SomeService
    self._initialized = true
end

function MyService:Start()
    assert(self._initialized, "Must call Init() before Start()")
    -- begin listening, set up connections, etc.
end

return MyService
```

**6. No wait() anywhere**
```lua
-- ❌ Never
wait(1)
game:WaitForChild("Thing")

-- ✅ Always
task.wait(1)
thing.ChildAdded:Wait()
```

---

## 📐 CODING STANDARDS

### Every File Must Start With

```lua
--!strict
--[[
    Class: FileName
    Description: What this module does and why it exists
    Dependencies: List of what it requires
    
    Usage:
        local MyService = require(path.to.MyService)
        MyService:Init(dependencies)
        MyService:Start()
]]
```

### Type Rules

- `--!strict` on every file — no exceptions
- `export type` for ALL shared types — never `local type`
- All types live in `src/shared/types/` — never define shared types inside a service file
- All function parameters and return values must be typed
- Never use `any` unless absolutely unavoidable — if you do, add a comment explaining why

```lua
-- ✅ Correct
export type PlayerState = "Idle" | "Attacking" | "Stunned" | "Dead"

function MyService:GetState(player: Player): PlayerState?
    return PlayerStates[player]
end

-- ❌ Wrong
local type PlayerState = string

function MyService:GetState(player)
    return PlayerStates[player]
end
```

### Function Length

Functions over 50 lines should be broken into smaller named functions. If you're over 50 lines and it feels necessary, add a comment explaining why it can't be split.

### Variable Naming

| Pattern | Use for |
|---|---|
| `PascalCase` | Types, Services, Controllers, module-level constants |
| `camelCase` | Local variables, function parameters |
| `SCREAMING_SNAKE` | True constants (never reassigned) |
| `_prefixed` | Private fields on service/controller tables |

### Error Handling

```lua
-- For expected failures (validation):
if not playerData then
    warn(`[ServiceName] No data for player {player.Name}`)
    return false, "Player data not found"
end

-- For unexpected failures (infrastructure):
local success, result = pcall(function()
    return DataStore:GetAsync(key)
end)
if not success then
    warn(`[DataService] DataStore read failed: {result}`)
    -- handle gracefully
end
```

---

## ⚔️ COMBAT & STATE RULES

### State Validation Is Mandatory Before Every Action

```lua
local function CanPerformAction(player: Player, actionState: PlayerState): (boolean, string?)
    local state = StateService:GetState(player)
    if state == "Dead" then return false, "Player is dead" end
    if state == "Stunned" then return false, "Player is stunned" end
    if state == "Ragdolled" then return false, "Player is ragdolled" end
    -- Add action-specific checks
    return true, nil
end
```

### State Transition Reference

Valid transitions — if it's not in this list, it's blocked:

| From | Can go to |
|---|---|
| Idle | Walking, Running, Jumping, Attacking, Blocking, Dodging, Casting, Stunned, Dead |
| Walking | Idle, Running, Jumping, Attacking, Blocking, Dodging, Casting, Stunned, Dead |
| Running | Idle, Walking, Jumping, Attacking, Dodging, Stunned, Dead |
| Attacking | Idle, Walking, Stunned, Dead |
| Blocking | Idle, Walking, Stunned, Dead |
| Casting | Idle, Walking, Stunned, Dead |
| Stunned | Idle, Dead |
| Dead | (terminal — ForceState admin only) |

### Anti-Cheat Non-Negotiables

- Damage is NEVER calculated by the client — server only
- Hitbox creation timing is client-side but position/result is server-validated
- Cooldowns are tracked server-side — client may cache for UI only
- Position delta is validated on server (anti-teleport)
- Rate limiting on every RemoteEvent handler

---

## 🔮 ASPECT SYSTEM RULES

All ability execution flows through AspectService on the server:

```
Client (keypress) → AbilityCastRequest → Server
Server → CanCastAbility() check → state + mana + cooldown + range
Server → SetState("Casting") → wait castTime → VFX stub → apply damage
Server → AbilityCastResult → Client (feedback)
```

VFX functions are always empty stubs until an animator implements them:
```lua
VFX_Function = function(caster: Player, targetPosition: Vector3?) 
    -- VFX STUB: [describe intended effect here]
    -- Implementation deferred — not a programmer task
end,
```

Communion abilities are always stubs — do not implement behavior.

---

## 🎒 INVENTORY RULES

- Default Roblox backpack is disabled via `task.defer(StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false))` in client runtime
- No Roblox `Tool` objects — all combat is service-driven
- Equip/unequip is server-validated — client sends request, server mutates PlayerData
- UI is built entirely in code — no Studio-placed ScreenGui elements
- Drag-and-drop between slots is deferred tech debt — do not implement

---

## 📦 GIT WORKFLOW

### Commit Format

```
<type>(#issue): Imperative short description

Optional body if context is needed.
```

Types: `feat` `fix` `refactor` `docs` `test` `chore`

Examples:
```
feat(#62): Add InventoryController Tab/I toggle and open/close tween
fix(#71): Prevent AspectService mana regen before player data loads
docs(#62): Update session log with inventory system completion
refactor(#55): Extract position validation to Utils.ValidatePosition
```

### When to Commit

Commit after every **logical unit** — one file, one system, one meaningful step. Never batch multiple files into one commit unless they are truly inseparable (e.g., a type file and the service that uses it in the same PR step).

### Push After Every Commit

```bash
git add .
git commit -m "feat(#XX): Description"
git push origin <branch>
```

Never let commits sit unpushed. The remote is the source of truth.

### Branch Strategy

```
main          ← stable, always deployable
develop       ← integration branch
feature/issue-XX-short-name  ← your working branch
hotfix/description           ← urgent fixes only
```

---

## 🧪 DEFINITION OF DONE

An issue is only closed when ALL of these are true:

- [ ] Code compiles with `--!strict` and zero type errors
- [ ] All acceptance criteria in the issue are met
- [ ] Manual test in Roblox Studio: zero errors or warnings in Output
- [ ] Client-server flow tested (if networked)
- [ ] No memory leaks — all Connections cleaned up on player leave or module unload
- [ ] Session log updated with what was built
- [ ] GitHub issue has a completion comment listing what was done
- [ ] All commits pushed to remote

If any item is false, the issue stays open.

---

## 🚦 AUTONOMOUS DECISION FRAMEWORK

When you hit ambiguity and there is no human to ask, use this priority order:

1. **This file** — if it's documented here, follow it
2. **Existing code patterns** — replicate what's already in the repo
3. **Industry best practices** — standard Roblox/Luau conventions
4. **Conservative default** — choose the simpler, more reversible option
5. **Document and move on** — create a `spec-gap` issue and use a placeholder

### When to STOP and create a blocked issue instead of guessing:

- Breaking change to a public API used by multiple systems
- Security or anti-cheat decision
- Scope is fundamentally unclear (can't write acceptance criteria)
- Third-party library integration with unclear behavior
- Architectural decision that affects multiple phases

### Common Spec Gaps and Their Placeholders

| Gap | Placeholder |
|---|---|
| Resonance Shard cost per branch depth | 100 / 250 / 500 (depth 1/2/3) |
| Ability Mana costs | 20 / 35 / 55 (depth 1/2/3) |
| Expression ability base damage | 15 / 30 / 50 (depth 1/2/3) |
| Resonance Shard loss on death | 15% of current Shards |
| Discipline stat differences | All equal until spec gap resolved |
| Weapon Groove depth thresholds | 50 / 150 / 300 uses (Whisper/Resonant/Soulbind) |

Always create a `spec-gap` labeled issue when you use a placeholder. Never silently invent numbers and leave them undocumented.

---

## 🎮 THE RING PROGRESSION PHILOSOPHY

**Status: DESIGN LOCKED** (Session NF-071)

The progression loop replaces generic "bandit beater" grinding with a **coherent beginner-to-endgame arc** that teaches through understanding, not reflexes.

Each ring teaches the player to comprehend something increasingly profound:
- **Ring 0 (Hearthspire):** Understand who you are (Aspect identity)
- **Ring 1 (Verdant Shelf):** Understand what you were (Hollowed mirrors, Witnessing, Codex)
- **Ring 2 (Ashfeld):** Understand what you're becoming (Omen, corruption, faction choice)
- **Ring 3 (Vael Depths):** Understand what world was (Memory Fragments, lore payoff)
- **Ring 4 (Gloam):** Understand what you're losing (Luminance drain, Streak)
- **Ring 5 (The Null):** Understand what darkness is (Convergence, endgame legacy)

**[→ Full Design Doc](../docs/Game%20Plan/Ring_Progression_Loop.md)**

---

## 🗺️ CURRENT PROJECT STATE (update this header each planning session)

**Last updated:** March 13, 2026 — Session NF-071 (Ring Progression Redesign)

| Phase | Status | Notes |
|---|---|---|
| Phase 0: Genesis | ✅ Complete | Repo, types, Rojo |
| Phase 1: Core Framework | ✅ Complete | DataService, NetworkService, StateService, Bootstrap |
| Phase 2: Combat & Movement | ✅ Complete | Hitbox, Combat, Defense, Movement |
| Phase 3: Aspect System | ✅ Complete | Types, Registry, Service, Controller, cooldowns, mana regen |
| Phase 3: Inventory | ✅ Complete | InventoryService + InventoryController (Deepwoken layout, NF-070) |
| Phase 3: Depth-1 Abilities | 🔄 In Progress | All OnActivate stubs — Ember first (#174) |
| **Ring 1: Progression Loop** | 🔄 In Progress | Hollowed enemies (#180), Witnessing (#181), Ember Points + Duskwalker (#182) — **Epic: #179** |
| Phase 4: World & Narrative | ⏳ Not Started | Dialogue (#177), enemy AI improvements, zone design |
| Phase 5: Polish & Launch | ⏳ Not Started | Anti-cheat audit, performance, final checklist |

**Next unblocked work (prioritized):**
1. **[#179 Epic](https://github.com/JoshuaKushnir/Nightfall/issues/179)** — Ring 1 Verdant Shelf progression loop (foundational for entire game)
2. [#180](https://github.com/JoshuaKushnir/Nightfall/issues/180) — Five Hollowed enemy types with distinct movesets
3. [#181](https://github.com/JoshuaKushnir/Nightfall/issues/181) — Witnessing system + Codex entries (observation rewards knowledge)
4. [#182](https://github.com/JoshuaKushnir/Nightfall/issues/182) — Ember Points + Duskwalker gate (player agency + readiness test)

---

## 📝 SESSION LOG FORMAT

Every session entry in `docs/session-log.md` must follow this structure:

```markdown
## Session NF-[XXX]: [One-line description]
**Date:** YYYY-MM-DD  
**Issues:** #XX, #YY

### What Was Built
- **File created/modified:** Brief description of what changed and why
- **File created/modified:** Brief description

### Integration Points
- How this connects to other systems
- What it enables that wasn't possible before

### Spec Gaps Encountered
- [Description] → Created issue #XX with placeholder value [N]

### Tech Debt Created
- [Description] → Tracked in issue #XX

### Next Session Should Start On
Issue #[NUMBER]: [TITLE] — [one sentence on why it's next]
```

---

## ❌ THINGS THAT ARE NEVER ACCEPTABLE

- Writing code without a GitHub issue
- Using `wait()` instead of `task.wait()`
- Defining shared types outside of `src/shared/types/`
- Calculating damage or state changes on the client without server validation
- Implementing VFX (empty stubs only)
- Implementing Communion abilities (stubs with design comments only)
- Implementing drag-and-drop inventory (logged as tech debt, deferred)
- Closing an issue before manually testing in Roblox Studio
- Ending a session without updating `docs/session-log.md`
- Leaving commits unpushed

---

## ✅ THINGS THAT ARE ALWAYS REQUIRED

- `--!strict` at the top of every file
- Standard documentation header on every module
- `export type` for every shared type
- Issue reference in every commit message
- Session log update at the end of every session
- Server validation of every client-sent action
- StateService for every state change
- GitHub issue progress comment when completing each major step

---

**GitHub:** [JoshuaKushnir/Nightfall](https://github.com/JoshuaKushnir/Nightfall)  
**Issues:** [github.com/JoshuaKushnir/Nightfall/issues](https://github.com/JoshuaKushnir/Nightfall/issues)  
**Session Log:** `docs/session-log.md`