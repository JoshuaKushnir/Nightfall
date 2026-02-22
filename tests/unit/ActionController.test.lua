--!strict
-- Basic API checks for ActionController (UI interactions are handled via input events,
-- which are covered by integration tests). These unit tests simply verify that the
-- newly‑added feint/cancel helper exists and that the public API hasn't regressed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionController = require(ReplicatedStorage.Client.controllers.ActionController)

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
            name = "PlayAction function exists",
            fn = function()
                assert(type(ActionController.PlayAction) == "function")
            end,
        },
        {
            name = "_PlayActionLocal function exists",
            fn = function()
                assert(type(ActionController._PlayActionLocal) == "function")
            end,
        },
        {
            name = "Fists weapon defines feint/parry cooldowns",
            fn = function()
                local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
                local fists = WeaponRegistry.Get("fists")
                assert(fists, "Fists config missing")
                assert(type(fists.FeintCooldown) == "number", "FeintCooldown missing on fists")
                assert(type(fists.ParryCooldown) == "number", "ParryCooldown missing on fists")
            end,
        },
        {
            name = "Cannot feint once hitbox has spawned",
            fn = function()
                -- simulate an in-progress attack
                ActionController.CurrentAction = {
                    Config = { Type = "Attack", Name = "test", Id = "atk1" },
                    TargetHit = nil,
                    CanFeint = false,        -- hitbox spawned already
                    IsActive = true,
                    Stop = function() error("should not be called") end,
                    Cleanup = function() error("should not be called") end,
                }

                ActionController.CancelCurrentAction()
                -- action should remain intact because feint was disallowed
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == "atk1", "Action was cancelled even though hitbox spawned")

                -- cleanup for other tests
                ActionController.CurrentAction = nil
            end,
        },
        {
            name = "Attack starts during feint cooldown but cannot be cancelled",
            fn = function()
                -- simulate global cooldown active
                ActionController.FeintCooldownEnd = tick() + 1
                local dummy = { Id = "atk_dummy", Type = "Attack", Name = "dummy" }

                -- playing should still work
                ActionController.CurrentAction = nil
                ActionController.PlayAction(dummy)
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == "atk_dummy", "Attack failed to start during feint cooldown")

                -- but cancelling immediately should be blocked by the global timer
                ActionController.CancelCurrentAction()
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == "atk_dummy", "Attack was cancelled despite cooldown")

                -- cleanup and reset
                ActionController.CurrentAction = nil
                ActionController.FeintCooldownEnd = 0
            end,
        },
        {
            name = "OnCharacterAdded clears feint cooldown",
            fn = function()
                ActionController.FeintCooldownEnd = tick() + 5
                ActionController:OnCharacterAdded({})
                assert(ActionController.FeintCooldownEnd == 0, "FeintCooldownEnd not reset on respawn")
            end,
        },
    },
}
