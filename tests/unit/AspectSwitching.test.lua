--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AspectService = require(ReplicatedStorage.Server.services.AspectService)
local InventoryService = require(ReplicatedStorage.Server.services.InventoryService)
local AbilityRegistry = require(ReplicatedStorage.Shared.modules.AbilityRegistry)
local DataService = require(ReplicatedStorage.Server.services.DataService)

return {
    name = "Aspect Switching Unit Tests",
    tests = {
        {
            name = "Switching Ash to Tide removes Ash moves and adds Tide moves",
            fn = function()
                local fakePlayer = { Name = "TestTide" }
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = { Inventory = {}, EquippedItems = {} }
                }

                -- We manually set some initial state for the Aspect to simulate existing state
                AspectService.SwitchAspect(fakePlayer, "Ash")
                
                local profile = DataService:GetProfile(fakePlayer)
                local hasAsh = false
                for _, item in ipairs(profile.Inventory) do
                    if item.Id == "move_AshenStep" then hasAsh = true end
                end
                assert(hasAsh, "Expected Ash move AshenStep in inventory")

                -- Switch to Tide
                local success, err = AspectService.SwitchAspect(fakePlayer, "Tide")
                assert(success, "Switching to Tide should succeed: " .. tostring(err))

                hasAsh = false
                local hasTide = false
                for _, item in ipairs(profile.Inventory) do
                    if item.Id == "move_AshenStep" then hasAsh = true end
                    if item.Id == "move_Current" then hasTide = true end
                end

                assert(not hasAsh, "Ash moves should be removed")
                assert(hasTide, "Tide moves should form the new moveset")
            end,
        },
        {
            name = "Switching Tide to nil removes Tide moves and restores base Ability items",
            fn = function()
                local fakePlayer = { Name = "TestNil" }
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = { Inventory = {}, EquippedItems = {} }
                }

                AspectService.SwitchAspect(fakePlayer, "Tide")
                
                local profile = DataService:GetProfile(fakePlayer)
                local hasTide = false
                for _, item in ipairs(profile.Inventory) do
                    if item.Id == "move_Current" then hasTide = true end
                end
                assert(hasTide, "Expected Tide move Current in inventory")

                -- Clear to nil
                local success, err = AspectService.SwitchAspect(fakePlayer, nil)
                assert(success, "Switching to nil should succeed: " .. tostring(err))

                hasTide = false
                local hasBase = false
                for _, item in ipairs(profile.Inventory) do
                    if item.Id == "move_Current" then hasTide = true end
                    if item.Id:match("^ability_") then hasBase = true end
                end

                assert(not hasTide, "Tide moves should be removed")
                assert(hasBase, "Base abilities should be restored")
            end,
        }
    }
}
