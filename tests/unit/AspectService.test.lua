--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AspectService = require(ReplicatedStorage.Server.services.AspectService)
local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)
local DataService = require(ReplicatedStorage.Server.services.DataService)

return {
    name = "AspectService Unit Tests",
    tests = {
        {
            name = "AssignAspect assigns a new aspect and sets initial depths",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {}
                }

                local success = AspectService.AssignAspect(fakePlayer, "Ash")
                assert(success == true, "expected AssignAspect to succeed")
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.AspectData, "profile should have AspectData after assign")
                assert(profile.AspectData.AspectId == "Ash")
                assert(profile.AspectData.Branches.Expression.Depth == 0)
            end,
        },
        {
            name = "DebugSetAspect force-assigns and maxes all branches",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {}
                }

                local ok = AspectService.DebugSetAspect(fakePlayer, "Tide")
                assert(ok == true, "expected debug set to succeed")
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.AspectData.AspectId == "Tide")
                assert(profile.AspectData.Branches.Expression.Depth == 3)
                assert(profile.AspectData.Branches.Form.Depth == 3)
                assert(profile.AspectData.Branches.Communion.Depth == 3)

                -- calling again with a different aspect should overwrite
                ok = AspectService.DebugSetAspect(fakePlayer, "Ember")
                assert(ok == true, "expected second debug set to succeed")
                profile = DataService:GetProfile(fakePlayer)
                assert(profile.AspectData.AspectId == "Ember")
            end,
        },
        {
            name = "DebugSetAspect returns false for invalid aspect",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {}
                }
                local ok = AspectService.DebugSetAspect(fakePlayer, "NotAReal")
                assert(ok == false, "invalid aspect should not be accepted")
            end,
        },
    },
}
