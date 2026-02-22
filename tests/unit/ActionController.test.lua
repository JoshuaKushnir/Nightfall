--!strict
-- Basic API checks for ActionController and feint cooldown behavior

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionController = require(ReplicatedStorage.Client.controllers.ActionController)
local ActionTypes = require(ReplicatedStorage.Shared.types.ActionTypes)

return {
    name = "ActionController Unit Tests",
    tests = {
        {
            name = "CancelCurrentAction helper defined",
            fn = function()
                assert(type(ActionController.CancelCurrentAction) == "function", "CancelCurrentAction missing")
            end,
        },
        {
            name = "Unarmed light attack allowed (cooldown branch)",
            fn = function()
                -- pretend no weapon equipped
                ActionController:Init({ WeaponController = { GetEquipped = function() return nil end } })
                ActionController.CurrentAction = nil
                ActionController.PlayAction(ActionTypes.ATTACK_LIGHT)
                assert(ActionController.CurrentAction, "Unarmed light attack blocked")
                ActionController.CurrentAction = nil
            end,
        },
        {
            name = "Feint cooldown prevents immediate re-feint",
            fn = function()
                -- create a mock current action
                ActionController.CurrentAction = {
                    Config = { Id = "atk1", Name = "test", Type = "Attack" },
                    TargetHit = nil,
                    CanFeint = true,
                    IsActive = true,
                    Stop = function() end,
                    Cleanup = function() end,
                }
                -- first cancel sets cooldown
                ActionController.CancelCurrentAction()
                local now = tick()
                -- recreate action so we can attempt cancel again
                ActionController.CurrentAction = {
                    Config = { Id = "atk1", Name = "test", Type = "Attack" },
                    TargetHit = nil,
                    CanFeint = true,
                    IsActive = true,
                    Stop = function() end,
                    Cleanup = function() end,
                }
                ActionController.CancelCurrentAction()
                -- since cooldown was immediate, second cancel should be ignored
                -- action should remain
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == "atk1", "Feint cooldown not enforced")
                -- clear for other tests
                ActionController.CurrentAction = nil
                ActionController.FeintCooldownEnd = 0
            end,
        },
    },
}
