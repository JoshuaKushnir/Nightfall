--!strict
-- Tests for HUD visibility toggle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PlayerHUDController = require(ReplicatedStorage.Client.controllers.PlayerHUDController)

return {
    name = "PlayerHUDController Visibility Tests",
    tests = {
        {
            name = "HUD toggles visible state via method",
            fn = function()
                -- prepare gui
                local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
                if not playerGui then
                    playerGui = Instance.new("ScreenGui")
                    playerGui.Name = "PlayerGui"
                    playerGui.Parent = Players.LocalPlayer
                end

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

                -- initial should be visible
                assert(PlayerHUDController:IsVisible(), "HUD should start visible")
                PlayerHUDController:SetVisible(false)
                assert(not PlayerHUDController:IsVisible(), "HUD did not hide")
                PlayerHUDController:SetVisible(true)
                assert(PlayerHUDController:IsVisible(), "HUD did not show")

                PlayerHUDController:Shutdown()
            end,
        },
    },
}
