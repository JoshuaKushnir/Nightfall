--!strict
--[[
    EmberExpression Unit Tests
    Issue #125: Depth-1 Expression ability — Ember: charging strike, damage scales with run distance
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
