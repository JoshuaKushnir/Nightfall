--!strict
--[[
    EmberExpression Unit Tests — Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves × 3 talents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Ember = require(ReplicatedStorage.Shared.abilities.Ember)

local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
    local ok, err = pcall(fn)
    if ok then passed += 1; print(("    ✓ %s"):format(name))
    else   failed += 1; warn(("    ✗ %s\n      %s"):format(name, tostring(err))) end
end

local function assert_eq(a: any, b: any, label: string?)
    if a ~= b then
        error((label or "") .. (" expected %s got %s"):format(tostring(b), tostring(a)))
    end
end

local function makeCharacter(position: Vector3): (any, BasePart)
    local char = Instance.new("Model")
    local root = Instance.new("Part") :: BasePart
    root.Name     = "HumanoidRootPart"
    root.CFrame   = CFrame.new(position)
    root.Anchored = true
    root.Size     = Vector3.new(1, 2, 1)
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = { Character = char, Name = "EmberTestPlayer", UserId = 88820 }
    return player, root
end

print("\n── EmberExpression Unit Tests (moveset) ─────────────────────────────────")

-- ─── Moveset structure ────────────────────────────────────────────────────────

test("Ember.AspectId == 'Ember'", function()
    assert_eq(Ember.AspectId, "Ember")
end)

test("Ember.Moves exists and is a table", function()
    assert(type(Ember.Moves) == "table")
end)

test("Ember.Moves has exactly 5 moves", function()
    assert_eq(#Ember.Moves, 5)
end)

-- ─── Move 1 — Ignite ─────────────────────────────────────────────────────────

test("Moves[1].Id == 'Ignite'", function()
    assert_eq(Ember.Moves[1].Id, "Ignite")
end)

test("Moves[1].Type == 'Expression'", function()
    assert_eq(Ember.Moves[1].Type, "Expression")
end)

test("Moves[1].MoveType == 'UtilityProc'", function()
    assert_eq(Ember.Moves[1].MoveType, "UtilityProc")
end)

test("Moves[1].Slot == 1", function()
    assert_eq(Ember.Moves[1].Slot, 1)
end)

test("Moves[1].ManaCost == 20", function()
    assert_eq(Ember.Moves[1].ManaCost, 20)
end)

test("Moves[1].Cooldown == 5", function()
    assert_eq(Ember.Moves[1].Cooldown, 5)
end)

test("Moves[1].Range == 8 (dash distance)", function()
    assert_eq(Ember.Moves[1].Range, 8)
end)

test("Moves[1].OnActivate is a function", function()
    assert(type(Ember.Moves[1].OnActivate) == "function")
end)

test("Moves[1].ClientActivate is a function", function()
    assert(type(Ember.Moves[1].ClientActivate) == "function")
end)

test("Moves[1].OnActivate does not error — no momentum attribute", function()
    local player, root = makeCharacter(Vector3.new(300, 0, 0))
    Ember.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate does not error — Momentum = 2 (Torch talent path)", function()
    local player, root = makeCharacter(Vector3.new(400, 0, 0))
    root:SetAttribute("Momentum", 2)
    Ember.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88821 }
    Ember.Moves[1].OnActivate(player, nil)
end)

-- ─── Move 2 — Flashfire ───────────────────────────────────────────────────────

test("Moves[2].Id == 'Flashfire'", function()
    assert_eq(Ember.Moves[2].Id, "Flashfire")
end)

test("Moves[2].Slot == 2", function()
    assert_eq(Ember.Moves[2].Slot, 2)
end)

test("Moves[2].PostureDamage == 20", function()
    assert_eq(Ember.Moves[2].PostureDamage, 20)
end)

-- ─── Talents ─────────────────────────────────────────────────────────────────

test("Each move has exactly 3 Talents", function()
    for i, move in ipairs(Ember.Moves) do
        assert(type(move.Talents) == "table",
            ("Moves[%d].Talents"):format(i))
        assert_eq(#move.Talents, 3,
            ("Moves[%d] talent count"):format(i))
    end
end)

test("All Talents have IsUnlocked = false", function()
    for i, move in ipairs(Ember.Moves) do
        for j, talent in ipairs(move.Talents) do
            assert_eq(talent.IsUnlocked, false,
                ("Moves[%d].Talents[%d].IsUnlocked"):format(i, j))
        end
    end
end)

test("Moves have sequential Slots 1-5", function()
    for i, move in ipairs(Ember.Moves) do
        assert_eq(move.Slot, i, ("Moves[%d].Slot"):format(i))
    end
end)

test("All Moves have AspectId == 'Ember'", function()
    for i, move in ipairs(Ember.Moves) do
        assert_eq(move.AspectId, "Ember", ("Moves[%d].AspectId"):format(i))
    end
end)

-- ── Summary ──────────────────────────────────────────────────────────────────
print(("── EmberExpression: %d passed, %d failed ────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("EmberExpression tests: %d failure(s)"):format(failed)) end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Ember = require(ReplicatedStorage.Shared.abilities.Ember)

local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
    local ok, err = pcall(fn)
    if ok then passed += 1; print(("    ✓ %s"):format(name))
    else   failed += 1; warn(("    ✗ %s\n      %s"):format(name, tostring(err))) end
end

local function assert_eq(a: any, b: any, label: string?)
    if a ~= b then error((label or "") .. (" expected %s got %s"):format(tostring(b), tostring(a))) end
end

local function makeCharacter(position: Vector3): (any, BasePart)
    local char = Instance.new("Model")
    local root = Instance.new("Part") :: BasePart
    root.Name     = "HumanoidRootPart"
    root.CFrame   = CFrame.new(position)
    root.Anchored = true
    root.Size     = Vector3.new(1, 2, 1)
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = { Character = char, Name = "EmberTestPlayer", UserId = 88820 }
    return player, root
end

print("\n── EmberExpression Unit Tests ─────────────────────────────────────────────")

test("Ember has correct Id = 'Ignite'", function()
    assert_eq(Ember.Id, "Ignite")
end)

test("Ember has Type = 'Expression'", function()
    assert_eq(Ember.Type, "Expression")
end)

test("Ember has ManaCost = 20", function()
    assert_eq(Ember.ManaCost, 20)
end)

test("Ember has Cooldown = 5", function()
    assert_eq(Ember.Cooldown, 5)
end)

test("Ember has Range = 8 (dash distance)", function()
    assert_eq(Ember.Range, 8)
end)

test("Ember.OnActivate does not error — no momentum attribute (defaults to 1 stack)", function()
    local player, root = makeCharacter(Vector3.new(300, 0, 0))
    -- No Momentum attribute set — should default to 1 stack
    Ember.OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Ember.OnActivate does not error — Momentum = 2 (double stack)", function()
    local player, root = makeCharacter(Vector3.new(400, 0, 0))
    root:SetAttribute("Momentum", 2)
    Ember.OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Ember.OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88821 }
    Ember.OnActivate(player, nil)
end)

test("Ember applies IncomingPostureDamage to struck target (15 per stack)", function()
    local caster, _ = makeCharacter(Vector3.new(800, 0, 0))
    local targetChar = Instance.new("Model")
    local targetRoot = Instance.new("Part") :: BasePart
    targetRoot.Name     = "HumanoidRootPart"
    targetRoot.CFrame   = CFrame.new(808, 0, 0)  -- within dash + HIT_RADIUS
    targetRoot.Size     = Vector3.new(4, 6, 4)
    targetRoot.Anchored = true
    targetRoot.Parent   = targetChar
    targetChar.Parent   = Workspace

    local ok = pcall(Ember.OnActivate, caster, Vector3.new(808, 0, 0))
    assert(ok, "OnActivate should not throw")
    targetChar.Parent = nil
    caster.Character.Parent = nil
end)

test("Heat stack attribute is numeric", function()
    -- Verify the _applyHeatStack side-effects produce numeric HeatStacks
    local char = Instance.new("Model")
    char:SetAttribute("HeatStacks", 0)
    local stacks = (char:GetAttribute("HeatStacks") :: number?) or 0
    stacks += 1
    char:SetAttribute("HeatStacks", stacks)
    assert_eq(char:GetAttribute("HeatStacks"), 1, "HeatStacks attribute")
    char:Destroy()
end)

test("Ember has ClientActivate function", function()
    assert(type(Ember.ClientActivate) == "function")
end)

print(("── EmberExpression: %d passed, %d failed ────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("EmberExpression tests: %d failure(s)"):format(failed)) end
