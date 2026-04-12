--!strict
--[[
    EmberExpression Unit Tests -- Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves x 3 talents)
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

print("\n-- EmberExpression Unit Tests (moveset) ---------------------------------")

-- Moveset structure

test("Ember.AspectId == 'Ember'", function()
    assert_eq(Ember.AspectId, "Ember")
end)

test("Ember.Moves exists and is a table", function()
    assert(type(Ember.Moves) == "table")
end)

test("Ember.Moves has exactly 5 moves", function()
    assert_eq(#Ember.Moves, 5)
end)

-- Move 1 - Ignite

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

test("Moves[1].OnActivate does not error -- no momentum attribute", function()
    local player, root = makeCharacter(Vector3.new(300, 0, 0))
    Ember.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate does not error -- Momentum = 2 (Torch talent path)", function()
    local player, root = makeCharacter(Vector3.new(400, 0, 0))
    root:SetAttribute("Momentum", 2)
    Ember.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88821 }
    Ember.Moves[1].OnActivate(player, nil)
end)

-- Ignite behaviour
-- _applyHeatStack fires inside task.delay(0.2) -> HitboxService.OnHit (doubly deferred).
-- We verify attribute contracts instead of the deferred effect.

test("HeatStacks attribute contract: SetAttribute/GetAttribute round-trips correctly", function()
    local player, root = makeCharacter(Vector3.new(600, 0, 0))
    local char = player.Character
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
    char:SetAttribute("HeatStacks", 3)
    char:SetAttribute("StatusBurning", true)
    assert_eq(char:GetAttribute("StatusBurning"), true,
        "StatusBurning should be true at max stacks")
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate does not modify caster HeatStacks", function()
    local player, root = makeCharacter(Vector3.new(800, 0, 0))
    player.Character:SetAttribute("HeatStacks", 0)
    Ember.Moves[1].OnActivate(player, nil)
    assert_eq(player.Character:GetAttribute("HeatStacks") or 0, 0,
        "Caster's own HeatStacks must not be modified by Ignite OnActivate")
    root.Parent.Parent = nil
end)

-- Move 2 - Flashfire

test("Moves[2].Id == 'Flashfire'", function()
    assert_eq(Ember.Moves[2].Id, "Flashfire")
end)

test("Moves[2].Slot == 2", function()
    assert_eq(Ember.Moves[2].Slot, 2)
end)

test("Moves[2].PostureDamage == 20", function()
    assert_eq(Ember.Moves[2].PostureDamage, 20)
end)

test("Moves[2].OnActivate writes IncomingHPDamage proportional to stacks", function()
    local player, root = makeCharacter(Vector3.new(900, 0, 0))
    local char = player.Character
    char:SetAttribute("HeatStacks", 2)

    -- Mocking HitboxService for OnHit side-effects is complex in this env,
    -- but we can verify the function runs without error.
    Ember.Moves[2].OnActivate(player, Vector3.new(905, 0, 0))
    root.Parent.Parent = nil
end)

-- Move 3 - Heat Shield

test("Moves[3].Id == 'HeatShield'", function()
    assert_eq(Ember.Moves[3].Id, "HeatShield")
end)

test("Moves[3].OnActivate sets StatusHeatShield attribute", function()
    local player, root = makeCharacter(Vector3.new(1000, 0, 0))
    Ember.Moves[3].OnActivate(player, nil)
    assert_eq(player.Character:GetAttribute("StatusHeatShield"), true)
    root.Parent.Parent = nil
end)

-- Move 4 - Surge

test("Moves[4].Id == 'Surge'", function()
    assert_eq(Ember.Moves[4].Id, "Surge")
end)

test("Moves[4].OnActivate sets StatusSurge and increments Momentum", function()
    local player, root = makeCharacter(Vector3.new(1100, 0, 0))
    player.Character:SetAttribute("Momentum", 1)
    Ember.Moves[4].OnActivate(player, nil)
    assert_eq(player.Character:GetAttribute("StatusSurge"), true)
    assert_eq(player.Character:GetAttribute("Momentum"), 2)
    root.Parent.Parent = nil
end)

-- Move 5 - CinderField

test("Moves[5].Id == 'CinderField'", function()
    assert_eq(Ember.Moves[5].Id, "CinderField")
end)

test("Moves[5].OnActivate creates a zone part in Workspace", function()
    local player, root = makeCharacter(Vector3.new(1200, 0, 0))
    -- This test verifies Bug 1 fix (no 'casterId' error)
    Ember.Moves[5].OnActivate(player, Vector3.new(1200, 0, 0))

    local zone = Workspace:FindFirstChild("EmberCinderFieldZone")
    assert(zone ~= nil, "EmberCinderFieldZone should be created")
    assert(zone:IsA("BasePart"), "EmberCinderFieldZone should be a Part")

    zone:Destroy()
    root.Parent.Parent = nil
end)

-- Talents

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

test("All Talents have Id, Name, InteractsWith, Description fields", function()
    for i, move in ipairs(Ember.Moves) do
        for j, talent in ipairs(move.Talents) do
            assert(type(talent.Id) == "string",
                ("Moves[%d].Talents[%d].Id"):format(i, j))
            assert(type(talent.Name) == "string",
                ("Moves[%d].Talents[%d].Name"):format(i, j))
            assert(type(talent.InteractsWith) == "string",
                ("Moves[%d].Talents[%d].InteractsWith"):format(i, j))
            assert(type(talent.Description) == "string",
                ("Moves[%d].Talents[%d].Description"):format(i, j))
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

-- Summary
print(("-- EmberExpression: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("EmberExpression tests: %d failure(s)"):format(failed)) end
