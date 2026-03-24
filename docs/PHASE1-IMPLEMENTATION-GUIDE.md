# Phase 1 Implementation Guide: Server & Code Optimizations

**Phase Duration:** Weeks 1-2
**Priority:** Critical (blocks Phases 2 & 4)
**Issues:** #189-#194

---

## Overview

Phase 1 establishes the foundation for all subsequent optimizations. These changes must be completed and tested before beginning Phase 2 (Combat) or Phase 4 (Network) work.

**Why Phase 1 is Critical:**
- Removes hot-path bottlenecks (service requires, attribute lookups)
- Provides unified profiling infrastructure (TickManager)
- Establishes caching patterns for other phases to follow
- Reduces debug overhead that masks other performance issues

---

## Issue #189: Service Require Refactoring

### Current Problem

Ability modules use `pcall(require(...))` inside OnHit callbacks:

```lua
-- Current pattern (SLOW - runs on every hit)
function Ember.OnHit(hitData: HitboxTypes.HitData)
    local success, CombatService = pcall(require, ReplicatedStorage.Server.services.CombatService)
    if not success then return end

    -- damage logic
end
```

**Why This Is Slow:**
- `require()` performs dictionary lookup every hit (~1000s/sec during combat)
- `pcall()` adds overhead for error handling
- Module caching doesn't prevent lookup overhead
- Luau optimizer can't optimize across pcall boundaries

### Target Pattern

Move requires to module scope:

```lua
-- Target pattern (FAST - runs once at module load)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatService = require(ReplicatedStorage.Server.services.CombatService)
local DummyService = require(ReplicatedStorage.Server.services.DummyService)
local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)

function Ember.OnHit(hitData: HitboxTypes.HitData)
    -- direct use - no lookup overhead
    CombatService:ValidateHit(...)
end
```

### Implementation Steps

**Step 1: Audit Ability Modules**

Check all 13 ability files for require patterns:

```bash
cd /home/runner/work/Nightfall/Nightfall
grep -n "pcall.*require" src/shared/abilities/*.lua
grep -n "require.*Service" src/shared/abilities/*.lua
```

**Step 2: Move Requires to Module Scope**

For each ability file:

1. Identify all services used in OnHit/OnActivate
2. Add requires at top after type imports:
   ```lua
   --!strict
   -- Type imports
   local HitboxTypes = require(script.Parent.Parent.types.HitboxTypes)

   -- Services (module scope)
   local CombatService = require(ReplicatedStorage.Server.services.CombatService)
   ```
3. Remove pcall wrappers from hot paths
4. Replace conditional requires with assertions (if needed)

**Step 3: Verify No Circular Dependencies**

Circular dependency check:
```bash
# Run Rojo sync and check for circular require errors
rojo build --output test.rbxl
```

If circular dep found:
- Use Init() phase dependency injection instead
- Pass service references through AbilitySystem.Init()
- Store in module-level `_services` table

**Step 4: Profile Before/After**

Profiling script (place in ServerScriptService):

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatService = require(ReplicatedStorage.Server.services.CombatService)

local startTime = tick()
local hitCount = 0

-- Simulate 1000 hits
for i = 1, 1000 do
    -- Trigger hit processing
    hitCount += 1
end

local elapsed = tick() - startTime
print(`[Profile] 1000 hits in {elapsed}s = {elapsed/1000*1000}ms per hit`)
```

Expected improvement: 10-15% reduction in combat loop frame time.

---

## Issue #190: Attribute Caching in Tight Loops

### Current Problem

CombatService damage processing reads attributes every frame:

```lua
-- Current pattern (SLOW - reads attributes 100+ times/frame)
function CombatService:_ProcessDamageAttributes()
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if not char then continue end

        local weapon = char:FindFirstChild("Weapon")
        if weapon then
            local damage = weapon:GetAttribute("Damage") -- SLOW: C++ call every frame
            local critChance = weapon:GetAttribute("CritChance") -- SLOW
            -- ...
        end
    end
end
```

**Why This Is Slow:**
- `GetAttribute()` is C++ boundary crossing (expensive)
- Attributes stored in hash map requiring lookup
- Values rarely change but read every frame (16ms intervals)
- No caching means redundant work

### Target Pattern

Cache attributes at equip time:

```lua
-- Add cache table to service
local _weaponCache = {} :: {[Player]: WeaponCache}

type WeaponCache = {
    Damage: number,
    CritChance: number,
    Range: number,
    LastUpdated: number,
}

function CombatService:_CacheWeaponAttributes(player: Player)
    local char = player.Character
    if not char then return end

    local weapon = char:FindFirstChild("Weapon")
    if not weapon then
        _weaponCache[player] = nil
        return
    end

    _weaponCache[player] = {
        Damage = weapon:GetAttribute("Damage") or 10,
        CritChance = weapon:GetAttribute("CritChance") or 0.15,
        Range = weapon:GetAttribute("Range") or 5,
        LastUpdated = tick(),
    }
end

function CombatService:_ProcessDamageAttributes()
    for _, player in Players:GetPlayers() do
        local cache = _weaponCache[player]
        if not cache then continue end

        local damage = cache.Damage -- FAST: table lookup
        local critChance = cache.CritChance -- FAST
        -- ...
    end
end
```

### Implementation Steps

**Step 1: Identify Attribute Reads in Hot Paths**

Search for GetAttribute in frame-rate loops:

```bash
grep -n "GetAttribute" src/server/services/CombatService.lua
grep -n "GetAttribute" src/server/services/PostureService.lua
grep -n "GetAttribute" src/server/services/MovementService.lua
```

**Step 2: Add Cache Tables**

For each service:

1. Add cache table at module scope
2. Define cache type
3. Implement cache population function
4. Implement cache invalidation function

**Step 3: Hook Cache Updates to Events**

Cache invalidation triggers:

```lua
-- CombatService weapon cache
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        char.ChildAdded:Connect(function(child)
            if child.Name == "Weapon" then
                CombatService:_CacheWeaponAttributes(player)
            end
        end)

        char.ChildRemoved:Connect(function(child)
            if child.Name == "Weapon" then
                _weaponCache[player] = nil
            end
        end)
    end)
end)

-- PostureService max posture cache
-- Invalidate on stat changes
DataService.OnStatChanged:Connect(function(player, statName)
    if statName == "Fortitude" or statName == "Willpower" then
        PostureService:_RecalculateMaxPosture(player)
    end
end)
```

**Step 4: Replace GetAttribute with Cache Lookups**

Replace:
```lua
local damage = weapon:GetAttribute("Damage")
```

With:
```lua
local cache = _weaponCache[player]
local damage = cache and cache.Damage or 10
```

**Step 5: Profile Before/After**

Expected improvement: 20%+ reduction in attribute read overhead.

---

## Issue #191: Centralized Tick Loops

### Current Problem

Multiple services connect to Heartbeat independently:

```lua
-- CombatService
RunService.Heartbeat:Connect(function(dt)
    CombatService:_ProcessDamageAttributes()
end)

-- HitboxService
RunService.Heartbeat:Connect(function(dt)
    HitboxService:TestHitbox()
end)

-- HollowedService
RunService.Heartbeat:Connect(function(dt)
    HollowedService:_TickAllAI(dt)
end)

-- 5+ more services...
```

**Problems:**
- Fragmented profiling (can't see unified tick cost)
- No execution order guarantees
- No tick budget tracking
- Difficult to debug performance issues

### Target Pattern

Single TickManager coordinating all ticks:

```lua
-- TickManager.lua
local TickManager = {}

type TickPriority = "PrePhysics" | "Physics" | "PostPhysics" | "UI"

type TickHandler = {
    Priority: TickPriority,
    Handler: (dt: number) -> (),
    BudgetMs: number?,
}

local _handlers: {TickHandler} = {}
local _tickBudgets: {[string]: number} = {}

function TickManager:Register(name: string, priority: TickPriority, handler: (dt: number) -> ())
    table.insert(_handlers, {
        Priority = priority,
        Handler = handler,
        BudgetMs = nil,
    })

    -- Sort by priority
    table.sort(_handlers, function(a, b)
        local priorities = {PrePhysics = 1, Physics = 2, PostPhysics = 3, UI = 4}
        return priorities[a.Priority] < priorities[b.Priority]
    end)
end

function TickManager:Start()
    RunService.Heartbeat:Connect(function(dt)
        for _, handler in _handlers do
            local start = tick()
            handler.Handler(dt)
            local elapsed = (tick() - start) * 1000

            -- Track budget
            _tickBudgets[tostring(handler.Handler)] = elapsed
        end
    end)
end

function TickManager:GetBudgets(): {[string]: number}
    return _tickBudgets
end

return TickManager
```

### Implementation Steps

**Step 1: Create TickManager Module**

Create `src/shared/modules/TickManager.lua` with registration and execution logic.

**Step 2: Migrate Services**

For each service with Heartbeat connection:

1. Remove direct Heartbeat:Connect()
2. Add TickManager registration in Init():
   ```lua
   function CombatService:Init(dependencies)
       local TickManager = dependencies.TickManager
       TickManager:Register("CombatService", "PostPhysics", function(dt)
           self:_ProcessDamageAttributes()
       end)
   end
   ```

**Step 3: Update Bootstrap**

In `src/server/runtime/init.lua`, initialize TickManager early:

```lua
local modules = {
    TickManager = require(ReplicatedStorage.Shared.modules.TickManager),
    -- ... other modules
}

-- Init phase
TickManager:Init({})

-- Start phase
TickManager:Start() -- Start tick loop first
```

**Step 4: Add Budget Monitoring**

Admin command to view tick budgets:

```lua
-- AdminConsoleController
Commands.TickBudget = function()
    local budgets = TickManager:GetBudgets()
    for name, ms in budgets do
        print(`{name}: {ms}ms`)
    end
end
```

Expected improvement: 5-10% overhead reduction from unified tick loop.

---

## Issue #192: Movement State Machine Caching

### Current Problem

StateService validates same transitions repeatedly:

```lua
function StateService:CanTransition(player: Player, fromState: PlayerState, toState: PlayerState): boolean
    -- Expensive validation every call (called 60+ times/sec per player)
    if fromState == "Attacking" then
        if toState == "Idle" or toState == "Walking" or toState == "Stunned" or toState == "Dead" then
            return true
        end
        return false
    end
    -- ... 50+ more lines of validation logic
end
```

**Problem:** Same transitions validated thousands of times but rules never change.

### Target Pattern

Cache validation results:

```lua
local _transitionCache: {[string]: boolean} = {}

function StateService:CanTransition(player: Player, fromState: PlayerState, toState: PlayerState): boolean
    -- Check cache first
    local cacheKey = fromState .. "_to_" .. toState
    if _transitionCache[cacheKey] ~= nil then
        return _transitionCache[cacheKey]
    end

    -- Perform validation (only on first call for this transition)
    local canTransition = false
    if fromState == "Attacking" then
        if toState == "Idle" or toState == "Walking" or toState == "Stunned" or toState == "Dead" then
            canTransition = true
        end
    end
    -- ...

    -- Cache result
    _transitionCache[cacheKey] = canTransition
    return canTransition
end
```

### Implementation Steps

**Step 1: Add Cache to StateService**

Add `_transitionCache` table at module scope.

**Step 2: Wrap CanTransition Logic**

Add cache check at start, cache population at end.

**Step 3: Cache Invalidation Strategy**

Cache should invalidate when:
- New state added to system (rare)
- State rules modified (development only)

For production: never invalidate (rules are static).

**Step 4: Pre-populate Cache (Optional Optimization)**

At Init(), pre-populate all valid transitions:

```lua
function StateService:Init()
    -- Pre-populate transition cache
    local states = {"Idle", "Walking", "Running", "Attacking", "Stunned", "Dead", ...}
    for _, from in states do
        for _, to in states do
            self:CanTransition(nil, from, to) -- Populate cache
        end
    end
end
```

Expected improvement: 30%+ reduction in state validation overhead.

---

## Issue #193: Debug Systems Gating

### Current Problem

Debug code runs in production:

```lua
-- HitboxService creates debug parts even when not debugging
function HitboxService:_CreateDebugVisualization(hitbox)
    local part = Instance.new("Part")
    part.Transparency = 0.5
    part.CanCollide = false
    part.Parent = workspace.DebugFolder
    -- ... more setup
end

-- Every hitbox creates debug part (memory waste)
```

### Target Pattern

Gate behind runtime flags:

```lua
-- DebugSettings.lua
local DebugSettings = {
    ShowHitboxes = false,
    VerboseLogging = false,
    ShowStateSyncPackets = false,
}

return DebugSettings

-- HitboxService.lua
local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)

function HitboxService:_CreateDebugVisualization(hitbox)
    if not DebugSettings.ShowHitboxes then
        return -- Early exit - no debug overhead
    end

    local part = Instance.new("Part")
    -- ... only runs if debug enabled
end
```

### Implementation Steps

**Step 1: Extend DebugSettings Module**

Add runtime toggle support:

```lua
local DebugSettings = {
    ShowHitboxes = false,
    VerboseLogging = false,
    ShowNetworkPackets = false,
}

function DebugSettings:Toggle(flag: string, enabled: boolean)
    if self[flag] ~= nil then
        self[flag] = enabled
        print(`[DebugSettings] {flag} = {enabled}`)
    end
end

return DebugSettings
```

**Step 2: Gate Debug Code**

Search for debug code:

```bash
grep -n "Instance.new.*Part.*Debug" src/**/*.lua
grep -n "warn(" src/server/services/*.lua | grep -i "debug"
```

Add gates:
```lua
if DebugSettings.VerboseLogging then
    warn(`[CombatService] Hit validation failed: {reason}`)
end
```

**Step 3: Add Admin Toggle Command**

```lua
-- AdminConsoleController
Commands.DebugToggle = function(flag, enabled)
    DebugSettings:Toggle(flag, enabled)
end
```

Expected improvement: 5%+ overhead reduction with debug disabled.

---

## Issue #194: Module Initialization Audit

### Current Problem

Heavy work at require-time slows server startup:

```lua
-- AnimationLoader.lua
local AnimationDatabase = require(script.Parent.AnimationDatabase)

-- Builds flat map at require-time (expensive)
local _flatDb = {}
for aspectName, aspectData in AnimationDatabase do
    for animName, animId in aspectData do
        _flatDb[aspectName .. "_" .. animName] = animId
    end
end
-- Server startup blocked while this runs
```

### Target Pattern

Move to Init() or lazy loading:

```lua
-- AnimationLoader.lua
local _flatDb = nil

function AnimationLoader:Init()
    task.spawn(function()
        _flatDb = {}
        for aspectName, aspectData in AnimationDatabase do
            for animName, animId in aspectData do
                _flatDb[aspectName .. "_" .. animName] = animId
            end
        end
        print("[AnimationLoader] Flat DB built")
    end)
end

function AnimationLoader:Get(key: string)
    while not _flatDb do
        task.wait()
    end
    return _flatDb[key]
end
```

### Implementation Steps

**Step 1: Profile Module Require Times**

Add profiling wrapper to bootstrap:

```lua
-- runtime/init.lua
local function requireWithProfile(path)
    local start = tick()
    local module = require(path)
    local elapsed = (tick() - start) * 1000
    if elapsed > 10 then
        warn(`[Profile] {path.Name} require took {elapsed}ms`)
    end
    return module
end
```

**Step 2: Identify Slow Modules**

Look for requires >10ms:
- AnimationLoader
- AspectRegistry
- AbilityRegistry
- WeaponRegistry

**Step 3: Refactor to Async Init**

Move expensive work to Init() with async execution.

**Step 4: Profile Startup Time**

Measure total server startup time before/after.

Expected improvement: 15%+ faster server startup.

---

## Testing Strategy

### Per-Issue Testing

For each issue:

1. **Profile Before**: Capture baseline metrics
2. **Implement Changes**: Make minimal, focused changes
3. **Profile After**: Capture improved metrics
4. **Manual Test**: Verify no behavior changes
5. **Type Check**: Ensure zero type errors with `--!strict`

### Phase 1 Integration Test

After all 6 issues complete:

1. **Full Profiling Run**: Capture all metrics
2. **Combat Stress Test**: 10-player combat scenario
3. **Memory Profile**: Check for leaks or increased usage
4. **Gameplay Test**: Verify no behavior changes

### Success Criteria

Phase 1 complete when:
- [ ] All 6 issues closed with acceptance criteria met
- [ ] Combat loop frame time reduced 15%+
- [ ] Attribute read overhead reduced 20%+
- [ ] State validation overhead reduced 30%+
- [ ] Server startup time reduced 15%+
- [ ] Zero type errors
- [ ] No gameplay behavior changes

---

## Rollout Order

Issues can be worked in parallel by different developers, but test integration frequently:

**Week 1:**
- #189 (Service Require) - High priority, enables other work
- #190 (Attribute Caching) - High priority, big impact
- #191 (TickManager) - Medium priority, infrastructure

**Week 2:**
- #192 (State Caching) - Medium priority, depends on understanding #191
- #193 (Debug Gating) - Low priority, easy wins
- #194 (Init Audit) - Low priority, document findings

**Integration Testing:** End of Week 2

---

## Troubleshooting

### Circular Dependency Errors

**Symptom:** "Module contains a circular require" error

**Solution:** Use dependency injection:
```lua
-- Instead of require at module scope
local CombatService = nil

function MyService:Init(dependencies)
    CombatService = dependencies.CombatService
end
```

### Cache Invalidation Bugs

**Symptom:** Stale cached values after equipment change

**Solution:** Add logging to cache invalidation:
```lua
function CombatService:_InvalidateWeaponCache(player: Player)
    warn(`[CombatService] Invalidating weapon cache for {player.Name}`)
    _weaponCache[player] = nil
end
```

### TickManager Execution Order

**Symptom:** Service depends on another service's tick running first

**Solution:** Use priority levels:
```lua
TickManager:Register("PhysicsService", "PrePhysics", ...) -- Runs first
TickManager:Register("CombatService", "PostPhysics", ...) -- Runs after
```

---

## Next Phase

After Phase 1 completes, proceed to:
- **Phase 2** (Combat optimization) - Requires #189, #190, #191
- **Phase 3** (Rendering) - Can start immediately (independent)

Phase 1 unblocks the most critical paths, enabling all subsequent optimization work.
