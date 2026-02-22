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
    },
}
