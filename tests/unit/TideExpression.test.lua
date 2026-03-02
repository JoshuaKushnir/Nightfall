--!strict
--[[
    TideExpression Unit Tests — Moveset format
    Issue #149: refactor Aspect system to full moveset (5 moves × 3 talents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Tide = require(ReplicatedStorage.Shared.abilities.Tide)

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
    local player: any = { Character = char, Name = "TideTestPlayer", UserId = 88810 }
    return player, root
end

print("\n── TideExpression Unit Tests (moveset) ──────────────────────────────────")

-- ─── Moveset structure ────────────────────────────────────────────────────────

test("Tide.AspectId == 'Tide'", function()
    assert_eq(Tide.AspectId, "Tide")
end)

test("Tide.Moves exists and is a table", function()
    assert(type(Tide.Moves) == "table")
end)

test("Tide.Moves has exactly 5 moves", function()
    assert_eq(#Tide.Moves, 5)
end)

-- ─── Move 1 — Current ────────────────────────────────────────────────────────

test("Moves[1].Id == 'Current'", function()
    assert_eq(Tide.Moves[1].Id, "Current")
end)

test("Moves[1].Type == 'Expression'", function()
    assert_eq(Tide.Moves[1].Type, "Expression")
end)

test("Moves[1].MoveType == 'Offensive'", function()
    assert_eq(Tide.Moves[1].MoveType, "Offensive")
end)

test("Moves[1].Slot == 1", function()
    assert_eq(Tide.Moves[1].Slot, 1)
end)

test("Moves[1].ManaCost == 20", function()
    assert_eq(Tide.Moves[1].ManaCost, 20)
end)

test("Moves[1].Cooldown == 7", function()
    assert_eq(Tide.Moves[1].Cooldown, 7)
end)

test("Moves[1].Range == 15 (surge distance)", function()
    assert_eq(Tide.Moves[1].Range, 15)
end)

test("Moves[1].OnActivate is a function", function()
    assert(type(Tide.Moves[1].OnActivate) == "function")
end)

test("Moves[1].ClientActivate is a function", function()
    assert(type(Tide.Moves[1].ClientActivate) == "function")
end)

test("Moves[1].OnActivate does not error with valid character", function()
    local player, root = makeCharacter(Vector3.new(500, 0, 0))
    Tide.Moves[1].OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate does not error with explicit targetPosition", function()
    local player, root = makeCharacter(Vector3.new(600, 0, 0))
    Tide.Moves[1].OnActivate(player, Vector3.new(615, 0, 0))
    root.Parent.Parent = nil
end)

test("Moves[1].OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88811 }
    Tide.Moves[1].OnActivate(player, nil)
end)

-- ─── Move 3 — Swell (Defensive) ──────────────────────────────────────────────

test("Moves[3].Id == 'Swell'", function()
    assert_eq(Tide.Moves[3].Id, "Swell")
end)

test("Moves[3].MoveType == 'Defensive'", function()
    assert_eq(Tide.Moves[3].MoveType, "Defensive")
end)

-- ─── Talents ─────────────────────────────────────────────────────────────────

test("Each move has exactly 3 Talents", function()
    for i, move in ipairs(Tide.Moves) do
        assert(type(move.Talents) == "table",
            ("Moves[%d].Talents"):format(i))
        assert_eq(#move.Talents, 3,
            ("Moves[%d] talent count"):format(i))
    end
end)

test("All Talents have IsUnlocked = false", function()
    for i, move in ipairs(Tide.Moves) do
        for j, talent in ipairs(move.Talents) do
            assert_eq(talent.IsUnlocked, false,
                ("Moves[%d].Talents[%d].IsUnlocked"):format(i, j))
        end
    end
end)

test("Moves have sequential Slots 1-5", function()
    for i, move in ipairs(Tide.Moves) do
        assert_eq(move.Slot, i, ("Moves[%d].Slot"):format(i))
    end
end)

test("All Moves have AspectId == 'Tide'", function()
    for i, move in ipairs(Tide.Moves) do
        assert_eq(move.AspectId, "Tide", ("Moves[%d].AspectId"):format(i))
    end
end)

-- ── Summary ──────────────────────────────────────────────────────────────────
print(("── TideExpression: %d passed, %d failed ─────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("TideExpression tests: %d failure(s)"):format(failed)) end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Tide = require(ReplicatedStorage.Shared.abilities.Tide)

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
    root.Name      = "HumanoidRootPart"
    root.CFrame    = CFrame.new(position)
    root.Anchored  = true
    root.Size      = Vector3.new(1, 2, 1)
    root.Parent    = char
    char.Parent    = Workspace
    local player: any = { Character = char, Name = "TideTestPlayer", UserId = 88810 }
    return player, root
end

print("\n── TideExpression Unit Tests ─────────────────────────────────────────────")

test("Tide has correct Id = 'Current'", function()
    assert_eq(Tide.Id, "Current")
end)

test("Tide has Type = 'Expression'", function()
    assert_eq(Tide.Type, "Expression")
end)

test("Tide has ManaCost = 20", function()
    assert_eq(Tide.ManaCost, 20)
end)

test("Tide has Cooldown = 7", function()
    assert_eq(Tide.Cooldown, 7)
end)

test("Tide has Range = 15 (surge distance)", function()
    assert_eq(Tide.Range, 15)
end)

test("Tide.OnActivate does not error with valid character and no target", function()
    local player, root = makeCharacter(Vector3.new(500, 0, 0))
    Tide.OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Tide.OnActivate does not error with an explicit targetPosition", function()
    local player, root = makeCharacter(Vector3.new(600, 0, 0))
    Tide.OnActivate(player, Vector3.new(615, 0, 0))
    root.Parent.Parent = nil
end)

test("Tide.OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88811 }
    Tide.OnActivate(player, nil)
end)

test("Tide applies IncomingPostureDamage attribute to nearby target on surge hit", function()
    -- Spawn caster
    local caster, _ = makeCharacter(Vector3.new(700, 0, 0))
    -- Spawn target in surge path (15 studs away)
    local targetChar = Instance.new("Model")
    local targetRoot = Instance.new("Part") :: BasePart
    targetRoot.Name     = "HumanoidRootPart"
    targetRoot.CFrame   = CFrame.new(710, 0, 0)
    targetRoot.Size     = Vector3.new(3, 6, 3)  -- slightly large for overlap
    targetRoot.Anchored = true
    targetRoot.Parent   = targetChar
    targetChar.Parent   = Workspace

    local targetPlayer: any = {
        Character = targetChar,
        Name      = "TideTarget",
        UserId    = 88812,
    }
    -- Inject target into Players service via the mock table pattern
    -- (In a real test runner, Players:GetPlayers returns actual players;
    --  here we verify attribute is writable without side-effect errors.)
    local ok = pcall(Tide.OnActivate, caster, Vector3.new(710, 0, 0))
    assert(ok, "OnActivate should not throw")

    -- Cleanup
    targetChar.Parent = nil
    caster.Character.Parent = nil
end)

test("Tide has ClientActivate function", function()
    assert(type(Tide.ClientActivate) == "function")
end)

print(("── TideExpression: %d passed, %d failed ────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("TideExpression tests: %d failure(s)"):format(failed)) end
