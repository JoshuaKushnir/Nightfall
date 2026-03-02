--!strict
--[[
    AshExpression Unit Tests
    Issue #123: Depth-1 Expression ability — Ash: forward dash strike with decoy afterimage
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Ash = require(ReplicatedStorage.Shared.abilities.Ash)

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

-- ─── Helper: fake player character ───────────────────────────────────────────

local function makeCharacter(position: Vector3): (any, BasePart)
    local char = Instance.new("Model")
    local root = Instance.new("Part") :: BasePart
    root.Name     = "HumanoidRootPart"
    root.CFrame   = CFrame.new(position)
    root.Anchored = true
    root.Parent   = char
    char.Parent   = Workspace
    local player: any = {
        Character = char,
        Name      = "AshTestPlayer",
        UserId    = 88801,
    }
    return player, root
end

-- ─────────────────────────────────────────────────────────────────────────────

print("\n── AshExpression Unit Tests ─────────────────────────────────────────────")

test("Ash has correct Id = 'AshenStep'", function()
    assert_eq(Ash.Id, "AshenStep")
end)

test("Ash has Type = 'Expression'", function()
    assert_eq(Ash.Type, "Expression")
end)

test("Ash has correct ManaCost = 20", function()
    assert_eq(Ash.ManaCost, 20)
end)

test("Ash has correct Cooldown = 5", function()
    assert_eq(Ash.Cooldown, 5)
end)

test("Ash has Range = 12 (dash distance)", function()
    assert_eq(Ash.Range, 12)
end)

test("Ash.OnActivate does not error with a valid character", function()
    local player, root = makeCharacter(Vector3.new(0, 0, 0))
    -- Should complete without error (effects are delayed via task.delay)
    Ash.OnActivate(player, nil)
    root.Parent.Parent = nil  -- cleanup
end)

test("Ash.OnActivate silently exits for player with no character", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88802 }
    -- Must not throw
    Ash.OnActivate(player, nil)
end)

test("Ash has ClientActivate function", function()
    assert(type(Ash.ClientActivate) == "function", "ClientActivate must be a function")
end)

test("Ash has CastTime = 0.15", function()
    assert_eq(Ash.CastTime, 0.15)
end)

-- ── Summary ──────────────────────────────────────────────────────────────────
print(("── AshExpression: %d passed, %d failed ────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("AshExpression tests: %d failure(s)"):format(failed)) end
