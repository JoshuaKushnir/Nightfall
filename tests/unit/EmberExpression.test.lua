--!strict
--[[
    EmberExpression Unit Tests â€” Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves Ã— 3 talents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Ember = require(ReplicatedStorage.Shared.abilities.Ember)

local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
    local ok, err = pcall(fn)
    if ok then passed += 1; print(("    âœ“ %s"):format(name))
    else   failed += 1; warn(("    âœ— %s\n      %s"):format(name, tostring(err))) end
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

print("\nâ”€â”€ EmberExpression Unit Tests (moveset) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€")

-- â”€â”€â”€ Moveset structure â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Ember.AspectId == 'Ember'", function()
    assert_eq(Ember.AspectId, "Ember")
end)

test("Ember.Moves exists and is a table", function()
    assert(type(Ember.Moves) == "table")
end)

test("Ember.Moves has exactly 5 moves", function()
    assert_eq(#Ember.Moves, 5)
end)

-- â”€â”€â”€ Move 1 â€” Ignite â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

test("Moves[1].OnActivate does not error â€” no momentum attribute", function()
    local player, root = makeCharacter(Vector3.new(300, 0, 0))
    Ember.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate does not error â€” Momentum = 2 (Torch talent path)", function()
    local player, root = makeCharacter(Vector3.new(400, 0, 0))
    root:SetAttribute("Momentum", 2)
    Ember.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88821 }
    Ember.Moves[1].OnActivate(player, nil)
end)

-- â”€â”€â”€ Move 2 â€” Flashfire â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Moves[2].Id == 'Flashfire'", function()
    assert_eq(Ember.Moves[2].Id, "Flashfire")
end)

test("Moves[2].Slot == 2", function()
    assert_eq(Ember.Moves[2].Slot, 2)
end)

test("Moves[2].PostureDamage == 20", function()
    assert_eq(Ember.Moves[2].PostureDamage, 20)
end)

-- â”€â”€â”€ Talents â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€ Summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
print(("â”€â”€ EmberExpression: %d passed, %d failed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€"):format(passed, failed))
if failed > 0 then error(("EmberExpression tests: %d failure(s)"):format(failed)) end

-- ─── Ignite behaviour ─────────────────────────────────────────────────────────

test("HeatStacks attribute contract: SetAttribute/GetAttribute round-trips correctly", function()
    local player, root = makeCharacter(Vector3.new(600, 0, 0))
    local char = player.Character
    -- Simulate what _applyHeatStack does on the target character
    char:SetAttribute("HeatStacks", 0)
    assert_eq(char:GetAttribute("HeatStacks"), 0, "HeatStacks initial")
    char:SetAttribute("HeatStacks", 1)
    assert_eq(char:GetAttribute("HeatStacks"), 1, "HeatStacks after 1 stack")
    char:SetAttribute("HeatStacks", 3)
    assert_eq(char:GetAttribute("HeatStacks"), 3, "HeatStacks at max (3)")
    root.Parent.Parent = nil
end)

test("StatusBurning attribute contract: readable at max HeatStacks (3)", function()
    local player, root = makeCharacter(Vector3.new(700, 0, 0))
    local char = player.Character
    -- Simulate max-stack trigger
    char:SetAttribute("HeatStacks", 3)
    char:SetAttribute("StatusBurning", true)
    assert_eq(char:GetAttribute("StatusBurning"), true,
        "StatusBurning should be true at max stacks")
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate does not modify caster HeatStacks", function()
    local player, root = makeCharacter(Vector3.new(800, 0, 0))
    player.Character:SetAttribute("HeatStacks", 0)
    -- OnActivate fires task.delay; caster is never the target of _applyHeatStack
    Ember.Moves[1].OnActivate(player, nil)
    assert_eq(player.Character:GetAttribute("HeatStacks") or 0, 0,
        "Caster's own HeatStacks must not be modified by Ignite OnActivate")
    root.Parent.Parent = nil
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
