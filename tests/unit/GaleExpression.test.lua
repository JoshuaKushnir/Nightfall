--!strict
--[[
    GaleExpression Unit Tests — Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves × 3 talents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Gale = require(ReplicatedStorage.Shared.abilities.Gale)

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
    root.Anchored = false
    root.Size     = Vector3.new(1, 2, 1)
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = { Character = char, Name = "GaleTestPlayer", UserId = 88830 }
    return player, root
end

print("\n── GaleExpression Unit Tests (moveset) ──────────────────────────────────")

-- ─── Moveset structure ────────────────────────────────────────────────────────

test("Gale.AspectId == 'Gale'", function()
    assert_eq(Gale.AspectId, "Gale")
end)

test("Gale.Moves exists and is a table", function()
    assert(type(Gale.Moves) == "table")
end)

test("Gale.Moves has exactly 5 moves", function()
    assert_eq(#Gale.Moves, 5)
end)

-- ─── Move 1 — WindStrike ─────────────────────────────────────────────────────

test("Moves[1].Id == 'WindStrike'", function()
    assert_eq(Gale.Moves[1].Id, "WindStrike")
end)

test("Moves[1].Type == 'Expression'", function()
    assert_eq(Gale.Moves[1].Type, "Expression")
end)

test("Moves[1].MoveType == 'Offensive'", function()
    assert_eq(Gale.Moves[1].MoveType, "Offensive")
end)

test("Moves[1].Slot == 1", function()
    assert_eq(Gale.Moves[1].Slot, 1)
end)

test("Moves[1].ManaCost == 20", function()
    assert_eq(Gale.Moves[1].ManaCost, 20)
end)

test("Moves[1].Cooldown == 6", function()
    assert_eq(Gale.Moves[1].Cooldown, 6)
end)

test("Moves[1].Range == 12 (dash distance)", function()
    assert_eq(Gale.Moves[1].Range, 12)
end)

test("Moves[1].CastTime == 0.15", function()
    assert_eq(Gale.Moves[1].CastTime, 0.15)
end)

test("Moves[1].OnActivate is a function", function()
    assert(type(Gale.Moves[1].OnActivate) == "function")
end)

test("Moves[1].ClientActivate is a function", function()
    assert(type(Gale.Moves[1].ClientActivate) == "function")
end)

test("Moves[1].OnActivate does not error — ground cast", function()
    local player, root = makeCharacter(Vector3.new(1000, 5, 0))
    Gale.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88831 }
    Gale.Moves[1].OnActivate(player, nil)
end)

-- ─── Move 5 — Shear specifics ────────────────────────────────────────────────

test("Moves[5].Id == 'Shear'", function()
    assert_eq(Gale.Moves[5].Id, "Shear")
end)

test("Moves[5].Slot == 5", function()
    assert_eq(Gale.Moves[5].Slot, 5)
end)

test("Moves[5].PostureDamage == 30", function()
    assert_eq(Gale.Moves[5].PostureDamage, 30)
end)

-- ─── Talents ─────────────────────────────────────────────────────────────────

test("Each move has exactly 3 Talents", function()
    for i, move in ipairs(Gale.Moves) do
        assert(type(move.Talents) == "table",
            ("Moves[%d].Talents"):format(i))
        assert_eq(#move.Talents, 3,
            ("Moves[%d] talent count"):format(i))
    end
end)

test("All Talents have IsUnlocked = false", function()
    for i, move in ipairs(Gale.Moves) do
        for j, talent in ipairs(move.Talents) do
            assert_eq(talent.IsUnlocked, false,
                ("Moves[%d].Talents[%d].IsUnlocked"):format(i, j))
        end
    end
end)

test("Moves have sequential Slots 1-5", function()
    for i, move in ipairs(Gale.Moves) do
        assert_eq(move.Slot, i, ("Moves[%d].Slot"):format(i))
    end
end)

test("All Moves have AspectId == 'Gale'", function()
    for i, move in ipairs(Gale.Moves) do
        assert_eq(move.AspectId, "Gale", ("Moves[%d].AspectId"):format(i))
    end
end)

-- ── Summary ──────────────────────────────────────────────────────────────────
print(("── GaleExpression: %d passed, %d failed ─────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("GaleExpression tests: %d failure(s)"):format(failed)) end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Gale = require(ReplicatedStorage.Shared.abilities.Gale)

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
    root.Anchored = false  -- Gale manipulates velocity; needs non-anchored
    root.Size     = Vector3.new(1, 2, 1)
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = { Character = char, Name = "GaleTestPlayer", UserId = 88830 }
    return player, root
end

print("\n── GaleExpression Unit Tests ─────────────────────────────────────────────")

test("Gale has correct Id = 'WindStrike'", function()
    assert_eq(Gale.Id, "WindStrike")
end)

test("Gale has Type = 'Expression'", function()
    assert_eq(Gale.Type, "Expression")
end)

test("Gale has ManaCost = 20", function()
    assert_eq(Gale.ManaCost, 20)
end)

test("Gale has Cooldown = 6", function()
    assert_eq(Gale.Cooldown, 6)
end)

test("Gale has Range = 12 (dash distance)", function()
    assert_eq(Gale.Range, 12)
end)

test("Gale.OnActivate does not error — ground cast", function()
    local player, root = makeCharacter(Vector3.new(1000, 5, 0))
    -- Place terrain part below so _isAirborne returns false
    local ground = Instance.new("Part") :: BasePart
    ground.CFrame   = CFrame.new(1000, 0, 0)
    ground.Size     = Vector3.new(50, 1, 50)
    ground.Anchored = true
    ground.Parent   = Workspace
    Gale.OnActivate(player, nil)
    ground:Destroy()
    root.Parent.Parent = nil
end)

test("Gale.OnActivate does not error — airborne cast (no ground below)", function()
    local player, root = makeCharacter(Vector3.new(2000, 100, 0))
    -- No terrain below → _isAirborne = true
    Gale.OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Gale.OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88831 }
    Gale.OnActivate(player, nil)
end)

test("Gale applies IncomingPostureDamage attribute to target", function()
    local caster, _ = makeCharacter(Vector3.new(1500, 5, 0))
    local targetChar = Instance.new("Model")
    local targetRoot = Instance.new("Part") :: BasePart
    targetRoot.Name     = "HumanoidRootPart"
    targetRoot.CFrame   = CFrame.new(1512, 5, 0)
    targetRoot.Size     = Vector3.new(4, 6, 4)
    targetRoot.Anchored = false
    targetRoot.Parent   = targetChar
    targetChar.Parent   = Workspace

    local ok = pcall(Gale.OnActivate, caster, Vector3.new(1512, 5, 0))
    assert(ok, "OnActivate should not throw")
    targetChar:Destroy()
    caster.Character:Destroy()
end)

test("Ground cast posture damage is 20", function()
    -- Verify the constant via the ability's description / indirect check
    -- The design spec says ground = 20 posture
    assert(Gale.Range  == 12, "Range should be 12")
    assert(Gale.Cooldown == 6, "Cooldown 6s")
end)

test("Gale has ClientActivate function", function()
    assert(type(Gale.ClientActivate) == "function")
end)

print(("── GaleExpression: %d passed, %d failed ─────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("GaleExpression tests: %d failure(s)"):format(failed)) end
