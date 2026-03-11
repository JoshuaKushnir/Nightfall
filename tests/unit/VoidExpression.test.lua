--!strict
--[[
    VoidExpression Unit Tests -- Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves x 3 talents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Void = require(ReplicatedStorage.Shared.abilities.Void)

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

local function assert_vec3_close(a: Vector3, b: Vector3, epsilon: number, label: string?)
    local d = (a - b).Magnitude
    if d > epsilon then
        error(("%s: distance %.3f > epsilon %.3f  |  got (%g,%g,%g) expected (%g,%g,%g)"):format(
            label or "vec3", d, epsilon,
            a.X, a.Y, a.Z,
            b.X, b.Y, b.Z))
    end
end

local function makeCharacter(position: Vector3): (any, BasePart)
    local char = Instance.new("Model")
    local root = Instance.new("Part") :: BasePart
    root.Name     = "HumanoidRootPart"
    root.CFrame   = CFrame.new(position)
    root.Anchored = false
    root.Size     = Vector3.new(1, 2, 1)
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = { Character = char, Name = "VoidTestPlayer", UserId = 88840 }
    return player, root
end

print("\n-- VoidExpression Unit Tests (moveset) ----------------------------------")

-- Moveset structure

test("Void.AspectId == 'Void'", function()
    assert_eq(Void.AspectId, "Void")
end)

test("Void.Moves exists and is a table", function()
    assert(type(Void.Moves) == "table")
end)

test("Void.Moves has exactly 5 moves", function()
    assert_eq(#Void.Moves, 5)
end)

-- Move 1 - Blink

test("Moves[1].Id == 'Blink'", function()
    assert_eq(Void.Moves[1].Id, "Blink")
end)

test("Moves[1].Type == 'Expression'", function()
    assert_eq(Void.Moves[1].Type, "Expression")
end)

test("Moves[1].MoveType == 'UtilityProc'", function()
    assert_eq(Void.Moves[1].MoveType, "UtilityProc")
end)

test("Moves[1].Slot == 1", function()
    assert_eq(Void.Moves[1].Slot, 1)
end)

test("Moves[1].ManaCost == 20", function()
    assert_eq(Void.Moves[1].ManaCost, 20)
end)

test("Moves[1].Cooldown == 4", function()
    assert_eq(Void.Moves[1].Cooldown, 4)
end)

test("Moves[1].CastTime == 0.1 (near-instant)", function()
    assert_eq(Void.Moves[1].CastTime, 0.1)
end)

test("Moves[1].Range == 10 (blink distance)", function()
    assert_eq(Void.Moves[1].Range, 10)
end)

test("Moves[1].OnActivate is a function", function()
    assert(type(Void.Moves[1].OnActivate) == "function")
end)

test("Moves[1].ClientActivate is a function", function()
    assert(type(Void.Moves[1].ClientActivate) == "function")
end)

test("Moves[1].OnActivate does not error -- forward blink, no nearby targets", function()
    local player, root = makeCharacter(Vector3.new(-500, 0, 0))
    Void.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

-- Blink behaviour -- all synchronous (root.CFrame set directly in OnActivate)

test("Moves[1].OnActivate sets StatusBlinkBoost on caster character", function()
    local player, root = makeCharacter(Vector3.new(-600, 0, 0))
    Void.Moves[1].OnActivate(player, nil)
    local boost = root.Parent:GetAttribute("StatusBlinkBoost")
    assert(boost == true, "StatusBlinkBoost should be true after Blink, got: " .. tostring(boost))
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate sets BlinkPostureBonus to 0.30 on caster", function()
    local player, root = makeCharacter(Vector3.new(-700, 0, 0))
    Void.Moves[1].OnActivate(player, nil)
    local bonus = root.Parent:GetAttribute("BlinkPostureBonus") :: number?
    assert_eq(bonus, 0.30, "BlinkPostureBonus")
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate sets BlinkBoostExpiry to a future tick", function()
    local player, root = makeCharacter(Vector3.new(-800, 0, 0))
    Void.Moves[1].OnActivate(player, nil)
    local expiry = root.Parent:GetAttribute("BlinkBoostExpiry") :: number?
    assert(type(expiry) == "number" and expiry > tick(),
        "BlinkBoostExpiry should be a future tick, got: " .. tostring(expiry))
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate teleports caster ~10 studs forward", function()
    local startPos = Vector3.new(-900, 0, 0)
    local player, root = makeCharacter(startPos)
    -- Face +X so the blink fires in the +X direction
    root.CFrame = CFrame.new(startPos, startPos + Vector3.new(1, 0, 0))
    Void.Moves[1].OnActivate(player, nil)
    local expectedPos = startPos + Vector3.new(10, 0, 0)
    assert_vec3_close(root.Position, expectedPos, 1.5, "Blink teleport distance")
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88841 }
    Void.Moves[1].OnActivate(player, nil)
end)

-- Move 3 - PhaseShift (Defensive)

test("Moves[3].Id == 'PhaseShift'", function()
    assert_eq(Void.Moves[3].Id, "PhaseShift")
end)

test("Moves[3].CastTime == 0 (instant)", function()
    assert_eq(Void.Moves[3].CastTime, 0)
end)

test("Moves[3].MoveType == 'Defensive'", function()
    assert_eq(Void.Moves[3].MoveType, "Defensive")
end)

-- Move 5 - IsolationField

test("Moves[5].Id == 'IsolationField'", function()
    assert_eq(Void.Moves[5].Id, "IsolationField")
end)

test("Moves[5].Slot == 5", function()
    assert_eq(Void.Moves[5].Slot, 5)
end)

-- Talents

test("Each move has exactly 3 Talents", function()
    for i, move in ipairs(Void.Moves) do
        assert(type(move.Talents) == "table",
            ("Moves[%d].Talents"):format(i))
        assert_eq(#move.Talents, 3,
            ("Moves[%d] talent count"):format(i))
    end
end)

test("All Talents have IsUnlocked = false", function()
    for i, move in ipairs(Void.Moves) do
        for j, talent in ipairs(move.Talents) do
            assert_eq(talent.IsUnlocked, false,
                ("Moves[%d].Talents[%d].IsUnlocked"):format(i, j))
        end
    end
end)

test("All Talents have Id, Name, InteractsWith, Description fields", function()
    for i, move in ipairs(Void.Moves) do
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
    for i, move in ipairs(Void.Moves) do
        assert_eq(move.Slot, i, ("Moves[%d].Slot"):format(i))
    end
end)

test("All Moves have AspectId == 'Void'", function()
    for i, move in ipairs(Void.Moves) do
        assert_eq(move.AspectId, "Void", ("Moves[%d].AspectId"):format(i))
    end
end)

-- Summary
print(("-- VoidExpression: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("VoidExpression tests: %d failure(s)"):format(failed)) end