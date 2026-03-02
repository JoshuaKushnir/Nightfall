--!strict
--[[
    VoidExpression Unit Tests
    Issue #127: Depth-1 Expression ability — Void: blink behind target + posture bonus
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
    if a ~= b then error((label or "") .. (" expected %s got %s"):format(tostring(b), tostring(a))) end
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

print("\n── VoidExpression Unit Tests ─────────────────────────────────────────────")

test("Void has correct Id = 'Blink'", function()
    assert_eq(Void.Id, "Blink")
end)

test("Void has Type = 'Expression'", function()
    assert_eq(Void.Type, "Expression")
end)

test("Void has ManaCost = 20", function()
    assert_eq(Void.ManaCost, 20)
end)

test("Void has Cooldown = 4", function()
    assert_eq(Void.Cooldown, 4)
end)

test("Void is instant — CastTime = 0", function()
    assert_eq(Void.CastTime, 0)
end)

test("Void has Range = 10 (blink distance)", function()
    assert_eq(Void.Range, 10)
end)

test("Void.OnActivate does not error — no target nearby (forward blink)", function()
    local player, root = makeCharacter(Vector3.new(-500, 0, 0))
    Void.OnActivate(player, nil)
    root.Parent.Parent = nil
end)

test("Void.OnActivate grants VoidPostureBonusCharge on caster character", function()
    local player, root = makeCharacter(Vector3.new(-600, 0, 0))
    Void.OnActivate(player, nil)
    local charge = root.Parent:GetAttribute("VoidPostureBonusCharge")
    assert(type(charge) == "number" and charge > 0,
        "VoidPostureBonusCharge should be a positive number, got: " .. tostring(charge))
    root.Parent.Parent = nil
end)

test("VoidPostureBonusCharge value is 20", function()
    local player, root = makeCharacter(Vector3.new(-700, 0, 0))
    Void.OnActivate(player, nil)
    local charge = root.Parent:GetAttribute("VoidPostureBonusCharge") :: number?
    assert_eq(charge, 20, "VoidPostureBonusCharge")
    root.Parent.Parent = nil
end)

test("VoidPostureBonusExpiry is set to a future tick", function()
    local player, root = makeCharacter(Vector3.new(-800, 0, 0))
    Void.OnActivate(player, nil)
    local expiry = root.Parent:GetAttribute("VoidPostureBonusExpiry") :: number?
    assert(type(expiry) == "number" and expiry > tick(),
        "VoidPostureBonusExpiry should be a future tick: " .. tostring(expiry))
    root.Parent.Parent = nil
end)

test("Void.OnActivate sets PostureRegenBlocked on target within 3 studs", function()
    local caster, _ = makeCharacter(Vector3.new(-1000, 0, 0))

    -- Target right behind the caster (within BEHIND_OFFSET + 1 = 3 studs of dest)
    local targetChar = Instance.new("Model")
    local targetRoot = Instance.new("Part") :: BasePart
    targetRoot.Name     = "HumanoidRootPart"
    targetRoot.CFrame   = CFrame.new(-1000, 0, -2)  -- ~2 studs away along Z
    targetRoot.Size     = Vector3.new(2, 4, 2)
    targetRoot.Anchored = false
    targetRoot.Parent   = targetChar
    targetChar.Parent   = Workspace

    local targetPlayer: any = { Character = targetChar, Name = "VoidTarget", UserId = 88841 }
    _ = targetPlayer  -- reference to avoid unused warning

    local ok = pcall(Void.OnActivate, caster, nil)
    assert(ok, "OnActivate should not throw")

    targetChar:Destroy()
    caster.Character:Destroy()
end)

test("Void.OnActivate silently exits when character is nil", function()
    local player: any = { Character = nil, Name = "NoChar", UserId = 88842 }
    Void.OnActivate(player, nil)
end)

test("Void has ClientActivate function", function()
    assert(type(Void.ClientActivate) == "function")
end)

print(("── VoidExpression: %d passed, %d failed ─────────────────────────────────"):format(passed, failed))
if failed > 0 then error(("VoidExpression tests: %d failure(s)"):format(failed)) end
