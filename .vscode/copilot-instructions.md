# Nightfall: Engineering Manifesto & Architecture Rules
**Last Updated:** February 12, 2026  
**Project:** Nightfall - Dark Fantasy Roblox RPG  
**Architecture:** Rojo + Luau (Strict Typing, Modular, Testable)

---

## 🚨 CRITICAL: MANDATORY WORKFLOW RULES (READ FIRST)

### ⚠️ COPILOT ISSUE-DRIVEN DEVELOPMENT (MOST IMPORTANT)
**Golden Rule: NO IMPLEMENTATION WITHOUT AN ISSUE**

1. **ALL IDEAS REQUIRE ISSUES FIRST:**
   - Feature ideas → Create/reference GitHub issue BEFORE coding
   - Bug fixes → Link to existing issue or create new one
   - Refactoring → Document in issue with scope and impact
   - Questions/confusion → Default to GitHub issues discussion or create `docs/TECHNICAL_DECISIONS.md` entry
   - **Never implement without issue backing** - Use GitHub issue board as approval mechanism

2. **IF NO ISSUE EXISTS FOR YOUR TASK:**
   - Check [GitHub Issues](https://github.com/JoshuaKushnir/Nightfall/issues) first
   - If not found, create new issue using `gh issue create` with proper labels
   - Use best practices and professional standards if unsure of implementation details
   - State assumptions in issue description
   - Wait for issue creation confirmation before proceeding

3. **BUG HANDLING PROTOCOL:**
   - If you discover a bug DURING implementation:
     - Stop implementation immediately
     - Create GitHub issue with `bug` label (if not using standard labels, use descriptive title)
     - Document exact reproduction steps in issue
     - Reference the original issue being worked on
     - Update session-log with bug discovery
     - Do NOT attempt to fix unless explicitly instructed (let human review)
   - If asked to fix a known bug:
     - Find existing GitHub issue
     - Move issue to "In Progress" state
     - Update issue with current progress
     - Close issue only when fully tested

4. **ISSUE LIFECYCLE MANAGEMENT:**
   - **Create:** Issue doesn't exist → Create with labels and description
   - **Update:** During development → Add comments with progress checkpoint every major step
   - **Review:** Before completion → Verify all acceptance criteria met
   - **Close:** Only when ALL acceptance criteria complete and tested → Close with completion summary
   - **Track:** Update session-log.md with issue progress and link

5. **WHEN CONFUSED OR AMBIGUOUS:**
   - Default to **GitHub issue discussion thread** - ask clarifying questions in issue comments
   - Reference professional standards and best practices in your response
   - Document decision rationale in session log
   - **Minimize human interaction** - figure it out using established patterns and conventions
   - If truly blocked, note in issue and mark as `blocked` label

---

### ⚠️ BEFORE STARTING ANY TASK:
1. **ALWAYS READ `docs/BACKLOG.md`** - Check for existing issues, planned work, and architectural decisions
2. **ALWAYS READ `docs/session-log.md`** - Understand what was done previously, active types, and technical debt
3. **VERIFY GITHUB ISSUE EXISTS** - Check [GitHub Issues](https://github.com/JoshuaKushnir/Nightfall/issues) for the task at hand
4. **IF ISSUE MISSING:** Create it using `gh issue create` with labels (`phase-X`, `priority`, `type`)
5. **CHECK DEPENDENCIES** - Review issue dependencies and ensure prerequisites are complete
6. **REFERENCE ISSUE IN ALL WORK** - Use issue number in code comments, commit messages, session log

### ⚠️ DURING EVERY TASK:
1. **UPDATE GITHUB ISSUE** - Add comment with progress checkpoint every major file/system creation
   - Format: `## Progress Update\n- [x] Task completed\n- [ ] Next step\n**Issue:** self-assigned`
2. **LOG ALL ACTIONS** to `docs/session-log.md` under the current session:
   - Files created/modified with brief description
   - New types or interfaces added
   - Architectural decisions made
   - Problems encountered and solutions applied
   - **Link to GitHub issue number** in all entries
3. **REFERENCE ISSUE NUMBERS** - Link all work to specific issues
   - Code comments: `// Issue #24: ProfileService wrapper implementation`
   - Commit messages: `feat(#24): Implement DataService profile loading`
   - Session log: Include issue number in all entries
4. **MAINTAIN TYPE CONSISTENCY** - Always check `src/shared/types` before creating new data structures
5. **PRESERVE CONTEXT** - If you discover additional requirements or edge cases:
   - Note them in GitHub issue comments
   - Update acceptance criteria if scope changed
   - Create linked issues if separate work discovered
   - Do NOT silence issues - always update GitHub

### ⚠️ AFTER COMPLETING ANY TASK:

1. **CLOSE GITHUB ISSUE (Only When Fully Complete):**
   - Verify ALL acceptance criteria are ✅ complete
   - Add final comment summarizing completion:
     ```
     ## Issue Complete
     - [x] All acceptance criteria met
     - Files created/modified: [list]
     - Testing performed: [list]
     - Related issues: [link any]
     - Ready for: [next phase/review]
     ```
   - Use GitHub CLI: `gh issue close <issue-number> --comment "Completion summary..."`
   - Do NOT close prematurely - only when fully implemented and tested

2. **UPDATE `docs/session-log.md`:**
   - Mark completed milestones with issue number
   - Add new types to "Active Global Types" section
   - Document any technical debt created (with links to issues created)
   - Note integration points and testing performed
   - Reference all GitHub issue numbers worked on
   - Summarize blockers or follow-up work needed

3. **VERIFY INTEGRATION:**
   - Ensure new code integrates with existing systems
   - Check that types are exported and imported correctly
   - Confirm no breaking changes to dependent systems
   - Test with related systems if applicable
   - Update session log with verification results

4. **DOCUMENT NEXT STEPS IN GITHUB:**
   - If blockers discovered, create new issue (link to original)
   - If follow-up work needed, create issue and link from completed issue
   - If refactoring opportunities found, add issue comment suggesting refactor
   - Update any dependent issues with status
   - Mark related issues as unblocked if prerequisites now complete

### 📋 ISSUE BOARD MANAGEMENT:
- **Creating New Issues:**
  - Use issue template format from BACKLOG.md
  - Assign proper labels: `phase-X`, `priority`, `type`
  - Define acceptance criteria clearly
  - Link related issues for context
- **Issue States:**
  - `⏳ Pending` - Not started, awaiting dependencies
  - `🔄 In Progress` - Currently being worked on
  - `✅ Complete` - Fully implemented and tested
  - `🔥 Blocked` - Waiting on external factor or decision
- **Priority Levels:**
  - `critical` - Blocks other work, must be done first
  - `high` - Important for phase completion
  - `medium` - Enhances functionality, not blocking
  - `low` - Nice to have, cosmetic

---

## 🎯 DECISION-MAKING & BEST PRACTICES (Minimize Human Interaction)

### When to Make Autonomous Decisions:
**You should proceed WITHOUT asking for approval when:**
- Decision follows established architectural patterns (Service/Controller, strict typing, DRY, etc.)
- Implementation aligns with code standards documented in copilot-instructions.md
- Best practices are generally accepted in the industry (e.g., error handling, state management)
- Technical decision is reversible or fixable with reasonable effort
- Specs are unambiguous and acceptance criteria are clear

### Decision Framework (In Order of Priority):
1. **Check copilot-instructions.md** - Follow documented patterns and standards first
2. **Check existing code** - Replicate patterns used in similar modules
3. **Check best practices** - Use professional/industry standards
4. **Check this decision-making framework** - Apply logic below
5. **Document in GitHub** - Add comment explaining decision rationale

### Specific Decision Categories:

**API/Function Design:**
- Use established patterns: Service methods, Controller callbacks, utility functions
- Naming: camelCase for functions/variables, PascalCase for types/classes
- Parameters: Type every parameter, provide defaults when reasonable
- Documentation: Add header comment with purpose, parameters, returns, example

**Architectural Choices:**
- **When to create a Service:** Shared state or logic needed across multiple systems
- **When to create a Utility:** Function used 2+ times or pure logic with no side effects
- **When to create a Controller:** Client-side logic tied to specific gameplay system
- **When to create a Type:** Data structure shared between multiple modules

**Error Handling:**
- All network calls: Use (success, result) tuple pattern
- All database operations: Implement retry logic with exponential backoff
- All user input: Validate and sanitize before use
- All risky operations: Wrap in pcall() or Result pattern

**Performance:**
- Avoid `wait()` during initialization - use signals instead
- Cache calculations that are repeated
- Use object pools for frequently created/destroyed instances
- Profile before optimizing (don't guess)

**Type Safety:**
- ALWAYS use `--!strict` at top of file
- Define explicit return types for all functions
- Use union types for known value sets
- Export types from dedicated type files

**Bug vs Feature Decision:**
- **Bug:** Unintended behavior, breaks acceptance criteria, regression
- **Feature:** New capability, enhancement, additional scope
- When unclear: Err on side of "bug" - create issue and note in GitHub

### Common Ambiguities & How to Resolve:

| Ambiguity | Default Approach | Document In |
|-----------|------------------|-------------|
| "Should I add feature X?" | Check issue acceptance criteria - if not listed, create new issue first | GitHub issue |
| "Which pattern should I use?" | Follow most similar existing code | Code comment + session log |
| "How much error handling?" | Assume all inputs are malicious (security mindset) | Module documentation |
| "When to refactor?" | Never during active task - create tech debt issue instead | GitHub with `tech-debt` label |
| "Performance concern?" | Profile first to confirm - document findings in issue | GitHub issue analysis |
| "Breaking change?" | Stop immediately - consult issue and mark issue as `blocked` | GitHub issue discussion |

### When to Stop and Escalate to Human:

**DO NOT PROCEED - Create GitHub Issue or Comment:**
- Breaking changes to existing public APIs
- Fundamental architectural decisions not covered in manifesto
- Security vulnerabilities or anti-cheat concerns
- Undefined scope or conflicting requirements
- Resource constraints (too complex to estimate)
- Third-party library integration with unclear licensing/compatibility

**Mark as `blocked` label and add GitHub comment:**
```
## Awaiting Human Review
- **Issue:** [Description of blocker]
- **Why:** [Reason can't proceed autonomously]
- **Options considered:** [List with pros/cons]
- **Recommendation:** [Your professional assessment]
- **Time sensitive:** [Yes/No]
```

---

## 1. System Memory & Session Tracking

### Session Intelligence System
Every coding session has persistent memory through interconnected documentation:

**Primary Memory Files:**
- **`docs/session-log.md`** - Session-by-session technical journal
  - Current session ID and date
  - Active global types registry
  - Last integrated system/module
  - Completed milestones checklist
  - Technical debt tracker
  - Pending issues and blockers
- **`docs/BACKLOG.md`** - Complete development roadmap
  - All phases and issues
  - Feature specifications
  - Acceptance criteria
  - Dependencies and blockers
  - Priority and status tracking

**Context Preservation Protocol:**
1. **Before Writing Code:**
   - Read both memory files
   - Identify active types from session log
   - Check BACKLOG for related issues
   - Verify no conflicting implementations exist
2. **During Development:**
   - Reference existing types in `src/shared/types`
   - Log significant decisions inline with comments
   - Track new types/interfaces created
3. **After Implementation:**
   - Update session log with details
   - Mark BACKLOG issues complete
   - Document integration points
   - Note any new technical debt

### Session Log Format Standards
```markdown
## Current Session ID: NF-XXX
**Date:** YYYY-MM-DD
**Epic:** Brief description of main focus

## Last Integrated System: ModuleName

### Active Global Types
- `TypeName` - Brief description and usage
- `AnotherType` - Brief description

### Technical Debt / Pending Issues
- [ ] Issue #X: Description with context
- [ ] TODO: Specific technical debt item

### Completed Milestones
- [x] Specific completed task with timestamp
```

---

## 2. Modular Architecture (Rojo/Luau)

### Service/Controller Pattern (The Foundation)
**Server-Side Services** (`src/server/services/`)
- Authoritative game logic and data management
- State validation and anti-cheat enforcement
- Database operations and player persistence
- Global event coordination
- **Naming:** Always end with `Service` (e.g., `DataService`, `CombatService`)
- **Structure:**
  ```lua
  --!strict
  --[[
      Class: ServiceName
      Description: What this service manages
      Dependencies: List required services
      Author: Project Nightfall
      Last Modified: YYYY-MM-DD
  ]]
  
  local ServiceName = {}
  ServiceName.__index = ServiceName
  
  -- Private state
  local isInitialized = false
  
  function ServiceName:Init()
      if isInitialized then
          warn("ServiceName already initialized")
          return
      end
      -- Setup code
      isInitialized = true
  end
  
  function ServiceName:Start()
      -- Start running logic after all services Init()
  end
  
  return ServiceName
  ```

**Client-Side Controllers** (`src/client/controllers/`)
- User interface logic and user input handling
- Local animations and visual feedback
- Client-side prediction (with server validation)
- UI state management
- **Naming:** Always end with `Controller` (e.g., `CombatController`, `UIController`)
- **Structure:** Mirror service structure but for client logic

**Network Boundary** (`src/shared/network/`)
- All client-server communication goes through defined RemoteEvents/RemoteFunctions
- **Naming:** `[Feature]Network.lua` defines all remotes for that feature
- **Type Safety:** Always define expected parameter types
- **Validation:** Server MUST validate ALL client inputs (trust nothing)
- **Rate Limiting:** Implement cooldowns for all client-initiated actions

### Dependency Injection & Initialization
**Initialization Order:**
1. All services call `Init()` first (setup phase, no dependencies)
2. All services call `Start()` second (dependencies safe to use)
3. Never use `wait()` or `task.wait()` during initialization

**Dependency Loading:**
```lua
-- GOOD: Signal-based provider
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateService = require(ReplicatedStorage.Shared.Modules.StateService)

-- BAD: Yielding during load
local StateService = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("StateService"))
```

### DRY (Don't Repeat Yourself) Utility First
**The Two-Use Rule:** If any logic is used in 2+ places, it MUST become a utility function.

**Utility Categories** (`src/shared/modules/`)
- **`MathUtils.lua`** - Vector math, magnitude checks, angle calculations, interpolation
- **`TableUtils.lua`** - Deep copy, merge, filter, map, reduce operations
- **`ValidationUtils.lua`** - Type checking, range validation, nil-safe operations
- **`RaycastUtils.lua`** - Common raycast patterns, hitbox detection, line-of-sight
- **`TweenUtils.lua`** - Reusable tween templates, animation helpers
- **`StringUtils.lua`** - Formatting, parsing, sanitization

**Utility Function Standards:**
```lua
--[[
    Function: UtilityName
    Description: What it does and when to use it
    Parameters:
        param1: Type - Description
        param2: Type - Description
    Returns: Type - Description
    Example:
        local result = UtilityName(value1, value2)
]]
export type InputType = {
    field: string
}

local function UtilityName(param1: InputType, param2: number): boolean
    -- Implementation
    return true
end
```

---

## 3. Combat & Gameplay Logic

### State-Machine Authoritative Design
**The Nexus:** `StateService` is the single source of truth for all character states.

**State Requirements:**
- Every player and NPC MUST have a registered state
- State changes MUST go through StateService (no direct modification)
- State transitions MUST be validated (can't go from Dead to Attacking)
- State changes MUST be replicated to clients for animations

**State Types** (from `src/shared/types/PlayerData.lua`):
```lua
export type PlayerState = 
    "Idle" | "Walking" | "Sprinting" | "Jumping" | 
    "Attacking" | "Casting" | "Blocking" | "Dodging" | 
    "Stunned" | "Ragdolled" | "Dead" | "Meditating"
```

**State Validation Pattern:**
Every action must check state before execution:
```lua
local function PerformAction(player: Player)
    local currentState = StateService:GetState(player)
    
    -- Block during invalid states
    if currentState == "Stunned" or currentState == "Dead" or currentState == "Attacking" then
        return false, "Cannot perform action during " .. currentState
    end
    
    -- Set new state
    StateService:SetState(player, "Attacking")
    
    -- Perform action logic
    -- ...
    
    -- Return to idle
    task.delay(duration, function()
        StateService:SetState(player, "Idle")
    end)
    
    return true
end
```

### Mantra Framework (Magic System)
**Mantra Definition Standard:**
```lua
export type Mantra = {
    Id: string,
    Name: string,
    Description: string,
    BaseDamage: number,
    ManaCost: number,
    CastTime: number, -- seconds
    Cooldown: number, -- seconds
    Range: number, -- studs
    Element: "Fire" | "Water" | "Wind" | "Earth" | "Lightning" | "Shadow" | "Light",
    VFX_Function: (caster: Player, target: Vector3) -> (),
    OnHit_Function: (caster: Player, target: Player, damage: number) -> (),
    RequiredLevel: number,
    RequiredStats: {
        Intelligence: number?,
        Willpower: number?
    }
}
```

**Mantra Execution Flow:**
1. **Validate State:** Check caster is in valid state
2. **Validate Resources:** Check mana cost and cooldown
3. **Validate Target:** Check range and line-of-sight
4. **Set State:** Set caster to "Casting" state
5. **Cast Time:** Wait for cast time (interruptible)
6. **Execute VFX:** Play visual effects
7. **Apply Damage:** Server calculates and applies damage
8. **Trigger OnHit:** Execute special effects
9. **Start Cooldown:** Begin cooldown timer
10. **Return State:** Return caster to "Idle"

### Combat Component System
Use composition over inheritance for character attributes:

**Component Types:**
- **HealthComponent:** Current/Max health, regeneration rate, damage history
- **ManaComponent:** Current/Max mana, regeneration rate, cost modifiers
- **PostureComponent:** Balance system for stagger mechanics
- **EquipmentComponent:** Worn items, stat modifiers
- **StatusComponent:** Active buffs/debuffs with durations

**Component Access Pattern:**
```lua
-- Get component from PlayerData
local healthComp = playerData.Components.Health
local currentHP = healthComp.Current
local maxHP = healthComp.Max

-- Update component
healthComp.Current = math.max(0, currentHP - damage)

-- Trigger events if needed
if healthComp.Current <= 0 then
    StateService:SetState(player, "Dead")
end
```

---

## 4. Coding Standards & Type Safety

### Strict Typing Enforcement
**Mandatory for ALL files:**
```lua
--!strict
```

**Type Definition Standards:**
- Use `export type` for all shared types
- Define explicit return types for all functions
- Use union types for known value sets
- Avoid `any` unless absolutely necessary (document why)

**Type Location Rules:**
- **Shared Types:** `src/shared/types/` - Used by both client and server
- **Service Types:** Define in service file if only used by that service
- **Network Types:** Define parameter types at network boundary

**Type Documentation:**
```lua
--[[
    Type: TypeName
    Description: What this type represents
    Used By: List of modules/services
    Example:
        local instance: TypeName = {
            field1 = "value",
            field2 = 42
        }
]]
export type TypeName = {
    field1: string,
    field2: number,
    optionalField: boolean?
}
```

### Code Quality Standards

**Function Complexity:**
- Max 50 lines per function (split if longer)
- Single responsibility - each function does ONE thing
- Clear input/output contracts with types
- Early returns for error cases

**Variable Naming:**
- `camelCase` for variables and functions
- `PascalCase` for types and classes
- `SCREAMING_SNAKE_CASE` for constants
- Descriptive names (avoid abbreviations unless obvious)

**Comments & Documentation:**
```lua
-- Single line comments for quick clarifications

--[[
    Multi-line comments for:
    - Function documentation
    - Complex algorithm explanation
    - Architecture decisions
]]

-- TODO: Specific task remaining (add to technical debt)
-- FIXME: Known bug to address (create issue)
-- HACK: Temporary solution (explain why and plan removal)
-- NOTE: Important contextual information
```

**Error Handling:**
```lua
-- Use Result pattern: return success, value_or_error
local function RiskyOperation(input: string): (boolean, string)
    if not input or input == "" then
        return false, "Input cannot be empty"
    end
    
    local success, result = pcall(function()
        -- Risky operation
        return processInput(input)
    end)
    
    if not success then
        warn("RiskyOperation failed:", result)
        return false, "Operation failed: " .. tostring(result)
    end
    
    return true, result
end

-- Usage
local success, result = RiskyOperation(userInput)
if not success then
    -- Handle error
    warn("Error:", result)
    return
end
-- Use result
print("Success:", result)
```

---

## 5. Testing & Validation

### Unit Testing Requirements
**Test Coverage Expectations:**
- All utility functions MUST have tests
- All service public methods MUST have tests
- All validation/calculation logic MUST have tests

**Test File Location:**
- `tests/shared/` for shared utilities
- `tests/server/` for services
- Mirror source file structure

**Test Structure:**
```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestModule = require(ReplicatedStorage.Shared.Modules.ModuleName)

return function()
    describe("ModuleName", function()
        describe("FunctionName", function()
            it("should handle valid input", function()
                local result = TestModule.FunctionName("valid")
                expect(result).to.equal(expected)
            end)
            
            it("should reject invalid input", function()
                expect(function()
                    TestModule.FunctionName(nil)
                end).to.throw()
            end)
            
            it("should handle edge cases", function()
                -- Test boundary conditions
            end)
        end)
    end)
end
```

### Integration Testing
**When to Write Integration Tests:**
- Service interactions (e.g., DataService + StateService)
- Network communication (RemoteEvent handlers)
- Complex workflows (combat execution, mantra casting)

**Integration Test Focus:**
- Does the data flow correctly between systems?
- Are state transitions handled properly?
- Are edge cases at boundaries caught?

### Manual Testing Checklist
Before marking any issue as complete, verify:
- [ ] Code runs without errors in Roblox Studio
- [ ] No warnings in output console
- [ ] Type checking passes (`--!strict` enabled)
- [ ] Functionality works as specified in acceptance criteria
- [ ] Edge cases tested (nil values, extreme numbers, empty tables)
- [ ] Performance acceptable (no lag or stuttering)
- [ ] Client-server sync working correctly
- [ ] UI responds appropriately (if applicable)

---

## 6. Documentation Standards

### Module Header Template
```lua
--!strict
--[[
    ================================
    Module: ModuleName
    Type: Service|Controller|Utility|Type
    ================================
    
    Description:
        Detailed description of what this module does,
        its responsibilities, and when to use it.
    
    Dependencies:
        - DependencyName: Why it's needed
        - AnotherDep: Purpose
    
    Public API:
        - FunctionName(params): returns - Description
        - AnotherFunction(params): returns - Description
    
    Usage Example:
        local Module = require(path.to.Module)
        local result = Module:FunctionName(args)
    
    Author: Project Nightfall
    Created: YYYY-MM-DD
    Last Modified: YYYY-MM-DD by [Reason]
    Related Issues: #X, #Y
    ================================
]]
```

### Inline Documentation Standards
**When to Add Inline Comments:**
- Complex algorithms or math
- Non-obvious business logic
- Workarounds or hacks
- Performance optimizations
- Architecture decisions

**What NOT to Comment:**
- Obvious code (e.g., `-- Set x to 5` above `x = 5`)
- Redundant type info (types should be explicit)
- Outdated comments (delete or update, never leave stale)

### README Standards
Every major system should have a README:
- **Purpose:** What problem does this solve?
- **Architecture:** High-level design diagram or explanation
- **Usage:** How to use this system
- **Configuration:** Any settings or constants
- **Testing:** How to test this system
- **Known Issues:** Current limitations or bugs

---

## 7. Performance & Optimization

### Roblox-Specific Performance Rules

**Instance Management:**
- Reuse instances with object pools (don't constantly create/destroy)
- Use `GetChildren()` sparingly (cache results if possible)
- Avoid `WaitForChild()` in loops (use single wait at startup)
- Debounce rapid events (especially user input)

**Memory Management:**
- Clean up connections when objects destroyed
- Use `Janitor` or `Maid` pattern for lifecycle management
- Delete old references to prevent memory leaks
- Be careful with closures capturing large objects

**Network Optimization:**
- Batch related data into single RemoteEvent calls
- Use unreliable events for non-critical data (position updates)
- Compress data when possible (send IDs instead of full objects)
- Limit network calls per second (rate limiting)

**Computational Efficiency:**
- Cache expensive calculations
- Use `ipairs` for arrays, `pairs` for dictionaries
- Avoid nested loops with large datasets
- Use `task.spawn` or `task.defer` for non-blocking operations
- Profile code with Roblox Microprofiler when optimizing

---

## 8. Security & Anti-Cheat

### Server Authority Principles
**Golden Rule:** NEVER trust the client.

**Validation Requirements:**
- All player actions MUST be validated server-side
- Check state, resources, cooldowns, range BEFORE executing
- Verify ownership (player can't affect other players' data)
- Validate magnitude and angle of actions (anti-teleport)
- Rate limit all client requests

**Data Sanitization:**
```lua
local function ValidateDamage(reported: number): number
    -- Don't trust client-calculated damage
    local MAX_DAMAGE = 1000
    return math.clamp(reported, 0, MAX_DAMAGE)
end

local function ValidatePosition(player: Player, position: Vector3): boolean
    local character = player.Character
    if not character or not character.PrimaryPart then
        return false
    end
    
    local currentPos = character.PrimaryPart.Position
    local distance = (position - currentPos).Magnitude
    
    -- Ensure player isn't teleporting
    local MAX_SPEED = 100 -- studs per second
    return distance <= MAX_SPEED * 2 -- 2 second buffer
end
```

### Exploit Prevention Patterns
- **Remote Spamming:** Implement cooldowns and rate limiting
- **Teleportation:** Validate position changes
- **Speed Hacking:** Monitor velocity and position delta
- **Stat Manipulation:** All stats stored and modified server-side only
- **Item Duplication:** Use session locks and transaction validation

---

## 9. Git & Version Control

### Commit Message Standards
```
<type>(#issue): Brief description

Longer description if needed explaining why this
change was made and any important context.

- List of changes
- Another change

Related: #issue_number
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

**Examples:**
- `feat(#15): Add CombatService damage calculation`
- `fix(#23): Prevent StateService race condition`
- `refactor(#8): Extract common raycast logic to Utils`
- `docs: Update session log with Phase 1 completion`

### Branching Strategy
- **`main`** - Stable, deployable code only
- **`develop`** - Integration branch for features
- **`feature/issue-X`** - Individual feature branches
- **`hotfix/description`** - Urgent production fixes

---

## 10. Project-Specific Patterns

### Nightfall-Specific Conventions

**State Transition Graph:**
```
Idle ↔ Walking ↔ Sprinting
  ↓       ↓         ↓
Jumping  Attacking  Casting
  ↓       ↓         ↓
Rolling  Blocking  Dodging
  ↓       ↓         ↓
Stunned → Ragdolled → Dead
          ↓
     Meditating
```

**Data Flow Architecture:**
```
Client Input → Client Controller → Network → Server Service → StateService
                                                    ↓
                                              Data Validation
                                                    ↓
                                             Execute Action
                                                    ↓
                                            Update PlayerData
                                                    ↓
                                        Replicate to Clients (Network)
                                                    ↓
                                        Client Controller → UI Update
```

**Namespace Organization:**
- `Nightfall.Combat.*` - All combat-related modules
- `Nightfall.Magic.*` - Mantra system modules
- `Nightfall.Data.*` - Data persistence and management
- `Nightfall.UI.*` - Interface and HUD systems
- `Nightfall.World.*` - World generation and NPCs

---

## ✅ Quality Checklist (Run Before Completing ANY Task)

### Issue Management Checklist:
- [ ] GitHub issue exists for all work (check [issues](https://github.com/JoshuaKushnir/Nightfall/issues))
- [ ] Issue has proper labels: `phase-X`, priority, type
- [ ] Issue was updated with progress checkpoints during work
- [ ] All acceptance criteria in issue are ✅ complete
- [ ] No new bugs discovered (if found, create linked issue)
- [ ] Session-log.md references GitHub issue number
- [ ] Commit messages include issue number (e.g., `feat(#24): Description`)
- [ ] Ready to close issue: All criteria met, tested, documented
- [ ] Issue will be closed with completion summary

### Pre-Commit Checklist:
- [ ] `docs/session-log.md` updated with current session progress and issue numbers
- [ ] GitHub issue linked and has progress comments
- [ ] All files have `--!strict` at the top
- [ ] All new types added to appropriate type definition file
- [ ] Module header documentation complete
- [ ] Public functions have parameter/return documentation
- [ ] No `wait()` or `WaitForChild()` in hot paths
- [ ] Server validates ALL client input
- [ ] Error handling implemented for risky operations
- [ ] Manual testing performed in Roblox Studio
- [ ] No console warnings or errors
- [ ] Commit message follows format: `<type>(#issue): Description`

### Code Review Checklist:
- [ ] Follows service/controller architectural pattern
- [ ] Uses composition over inheritance
- [ ] No code duplication (utilities extracted)
- [ ] State changes go through StateService
- [ ] Types are explicit and accurate
- [ ] Functions under 50 lines
- [ ] Descriptive variable/function names
- [ ] Comments explain "why" not "what"
- [ ] Performance considerations addressed
- [ ] Security implications considered
- [ ] GitHub issue ready to close (all criteria met)

---

## 🎯 Remember: GitHub Issues First, Then Code
- **NO IMPLEMENTATION WITHOUT AN ISSUE** - Check [GitHub Issues](https://github.com/JoshuaKushnir/Nightfall/issues) first
- Take time to check the issue board before starting
- Log progress in GitHub issue comments during development
- Update and close issues when complete
- When confused, use best practices and decision framework above
- Minimize human interaction - document decisions in GitHub
- Test manually before closing issue

**Single Source of Truth:** [GitHub Issue Board](https://github.com/JoshuaKushnir/Nightfall/issues)  
**Session Memory:** Keep [session-log.md](../docs/session-log.md) updated with issue numbers  
**Code Standards:** This document + [BACKLOG.md](../docs/BACKLOG.md)

# Project Nightfall: Session Intelligence Log
