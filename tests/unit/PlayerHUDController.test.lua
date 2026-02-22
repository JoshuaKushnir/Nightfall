--!strict
-- PlayerHUDController unit tests

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerHUDController = require(ReplicatedStorage.Client.controllers.PlayerHUDController)

return {
    name = "PlayerHUDController Unit Tests",
    tests = {
        {
            name = "HUD creates posture and luminance elements",
            fn = function()
                -- ensure PlayerGui exists and is clean
                local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
                if not playerGui then
                    playerGui = Instance.new("ScreenGui")
                    playerGui.Name = "PlayerGui"
                    playerGui.Parent = Players.LocalPlayer
                end

                -- initialize with dummy dependencies
                PlayerHUDController:Init({
                    StateSyncController = {
                        GetProfileLoadedSignal = function() return {Connect = function() end} end,
                        GetProfileUpdatedSignal = function() return {Connect = function() end} end,
                        GetStateChangedSignal = function() return {Connect = function() end} end,
                        GetCurrentProfile = function() return nil end,
                        GetCurrentState = function() return nil end,
                    },
                    MovementController = {},
                })

                PlayerHUDController:Start()

                local hud = playerGui:WaitForChild("PlayerHUD", 5)
                assert(hud, "PlayerHUD ScreenGui not created")
                local frame = hud:WaitForChild("HUDFrame", 5)
                assert(frame:FindFirstChild("PostureContainer"), "Posture UI missing")
                assert(frame:FindFirstChild("LuminanceContainer"), "Luminance UI missing")

                -- cleanup
                PlayerHUDController:Shutdown()
            end,
        },
    },
}
