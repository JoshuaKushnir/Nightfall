--!strict
-- Tests ensuring zone trigger parts are ignored by climb/ledge detection

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local LedgeCatchState = require(ReplicatedStorage.Shared.movement.states.LedgeCatchState)
local ClimbState = require(ReplicatedStorage.Shared.movement.states.ClimbState)

return function()
    describe("Zone trigger filtering", function()
        it("Utils.GetZoneTriggerParts returns parts named ZoneTrigger*", function()
            local part = Instance.new("Part")
            part.Name = "ZoneTrigger_Test"
            part.Anchored = true
            part.Parent = Workspace

            local parts = Utils.GetZoneTriggerParts()
            expect(#parts).to.be.greaterThan(0)
            expect(table.find(parts, part)).to.be.ok()
            -- cleanup
            part:Destroy()
        end)

        it("LedgeCatch cannot see a ledge when only a zone part is present", function()
            local zone = Instance.new("Part")
            zone.Name = "ZoneTrigger_Block"
            zone.Size = Vector3.new(10, 10, 1)
            zone.CFrame = CFrame.new(0, 5, 5)
            zone.Anchored = true
            zone.Parent = Workspace

            -- minimal character context
            local char = Instance.new("Model"); char.Name = "Char"
            local root = Instance.new("Part"); root.Name = "HumanoidRootPart"; root.Parent = char
            local humanoid = Instance.new("Humanoid"); humanoid.Parent = char
            char.Parent = Workspace

            local ctx = {Character = char, RootPart = root, Humanoid = humanoid, Blackboard = {}}

            local canCatch, _ = LedgeCatchState.CanCatch(ctx)
            expect(canCatch).to.equal(false)

            -- also test climb
            local didClimb = ClimbState.TryStart(ctx)
            expect(didClimb).to.equal(false)

            -- cleanup
            zone:Destroy()
            char:Destroy()
        end)
    end)
end