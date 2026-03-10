--!strict
--[[
    AshExpression Unit Tests â€” Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves Ã— 3 talents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Ash = require(ReplicatedStorage.Shared.abilities.Ash)

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
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = { Character = char, Name = "AshTestPlayer", UserId = 88801 }
    return player, root
end

print("\nâ”€â”€ AshExpression Unit Tests (moveset) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€")

-- â”€â”€â”€ Moveset structure â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Ash.AspectId == 'Ash'", function()
    assert_eq(Ash.AspectId, "Ash")
end)

test("Ash.DisplayName == 'Ash'", function()
    assert_eq(Ash.DisplayName, "Ash")
end)

test("Ash.Moves exists and is a table", function()
    assert(type(Ash.Moves) == "table", "Ash.Moves should be a table")
end)

test("Ash.Moves has exactly 5 moves", function()
    assert_eq(#Ash.Moves, 5)
end)

-- â”€â”€â”€ Move 1 â€” AshenStep â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Moves[1].Id == 'AshenStep'", function()
    assert_eq(Ash.Moves[1].Id, "AshenStep")
end)

test("Moves[1].Type == 'Expression'", function()
    assert_eq(Ash.Moves[1].Type, "Expression")
end)

test("Moves[1].MoveType == 'Offensive'", function()
    assert_eq(Ash.Moves[1].MoveType, "Offensive")
end)

test("Moves[1].Slot == 1", function()
    assert_eq(Ash.Moves[1].Slot, 1)
end)

test("Moves[1].ManaCost == 20", function()
    assert_eq(Ash.Moves[1].ManaCost, 20)
end)

test("Moves[1].Cooldown == 5", function()
    assert_eq(Ash.Moves[1].Cooldown, 5)
end)

test("Moves[1].Range == 12", function()
    assert_eq(Ash.Moves[1].Range, 12)
end)

test("Moves[1].CastTime == 0.15", function()
    assert_eq(Ash.Moves[1].CastTime, 0.15)
end)

test("Moves[1].OnActivate is a function", function()
    assert(type(Ash.Moves[1].OnActivate) == "function")
end)

test("Moves[1].ClientActivate is a function", function()
    assert(type(Ash.Moves[1].ClientActivate) == "function")
end)

test("Moves[1].OnActivate does not error with valid character", function()
    local player, root = makeCharacter(Vector3.new(0, 0, 0))
    Ash.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits for nil character", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88802 }
    Ash.Moves[1].OnActivate(player, nil)
end)

-- â”€â”€â”€ AshenStep behaviour â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Moves[1].OnActivate spawns AshenStepAfterimage Part at origin", function()
    local startPos = Vector3.new(500, 0, 0)
    local player, root = makeCharacter(startPos)
    -- task.spawn(_spawnAfterimage) runs synchronously â€” Part lands this frame
    Ash.Moves[1].OnActivate(player, nil)
    local afterimage = Workspace:FindFirstChild("AshenStepAfterimage")
    assert(afterimage ~= nil, "AshenStepAfterimage Part should exist in Workspace")
    assert(afterimage:IsA("BasePart"),
        "AshenStepAfterimage should be a BasePart")
    local dist = (afterimage.Position - startPos).Magnitude
    assert(dist < 2,
        ("Afterimage should be within 2 studs of origin, got %.2f"):format(dist))
    afterimage:Destroy()
    root.Parent.Parent = nil
end)
-- â”€â”€â”€ Talents â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Each move has exactly 3 Talents", function()
    for i, move in ipairs(Ash.Moves) do
        assert(type(move.Talents) == "table",
            ("Moves[%d].Talents should be a table"):format(i))
        assert_eq(#move.Talents, 3,
            ("Moves[%d] talent count"):format(i))
    end
end)

test("All Talents have IsUnlocked = false", function()
    for i, move in ipairs(Ash.Moves) do
        for j, talent in ipairs(move.Talents) do
            assert_eq(talent.IsUnlocked, false,
                ("Moves[%d].Talents[%d].IsUnlocked"):format(i, j))
        end
    end
end)

test("All Talents have Id, Name, InteractsWith, Description fields", function()
    for i, move in ipairs(Ash.Moves) do
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

-- â”€â”€â”€ Slots are sequential 1-5 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("Moves have sequential Slots 1-5", function()
    for i, move in ipairs(Ash.Moves) do
        assert_eq(move.Slot, i, ("Moves[%d].Slot"):format(i))
    end
end)

-- â”€â”€â”€ All moves have AspectId == 'Ash' â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

test("All Moves have AspectId == 'Ash'", function()
    for i, move in ipairs(Ash.Moves) do
        assert_eq(move.AspectId, "Ash", ("Moves[%d].AspectId"):format(i))
    end
end)

-- â”€â”€ Summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
print(("â”€â”€ AshExpression: %d passed, %d failed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€"):format(passed, failed))
if failed > 0 then error(("AshExpression tests: %d failure(s)"):format(failed)) end

        end
    end
end)

test("All Talents have Id, Name, InteractsWith, Description fields", function()
    for i, move in ipairs(Ash.Moves) do
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

-- ─── Slots are sequential 1-5 ─────────────────────────────────────────────

test("Moves have sequential Slots 1-5", function()
    for i, move in ipairs(Ash.Moves) do
        assert_eq(move.Slot, i, ("Moves[%d].Slot"):format(i))
    end
end)

-- ─── All moves have AspectId == 'Ash' ────────────────────────────────────────

test("All Moves have AspectId == 'Ash'", function()
    for i, move in ipairs(Ash.Moves) do
        assert_eq(move.AspectId, "Ash", ("Moves[%d].AspectId"):format(i))
    end
end)

-- ── Summary ──────────────────────────────────────────────────────────────────
print(("── AshExpression: %d passed, %d failed ──────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("AshExpression tests: %d failure(s)"):format(failed)) end
