--!strict
--[[
    AspectController.lua

    Issue #12: Client-side handler for Aspect inputs and UI
    Epic: Phase 3 - Mantra / Aspect System

    Handles keybinds for abilities, receives server sync events, and queues
    requests to cast abilities or invest shards. Keeps local cooldown state
    for input gating.

    Dependencies: NetworkProvider, InputService (if exists), Utils
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)
local AspectTypes = require(ReplicatedStorage.Shared.types.AspectTypes)
local NetworkTypes = require(ReplicatedStorage.Shared.types.NetworkTypes)

local localPlayer = Players.LocalPlayer

local AspectController = {}
AspectController._cooldowns = {} -- abilityId -> expiry tick
AspectController._aspectData: AspectTypes.PlayerAspectData? = nil
AspectController._keybinds: {[Enum.KeyCode]: string?} = {}

-- default keybinds (Z,X,C,V)
AspectController._keybinds = {
    [Enum.KeyCode.Z] = nil,
    [Enum.KeyCode.X] = nil,
    [Enum.KeyCode.C] = nil,
    [Enum.KeyCode.V] = nil,
}

function AspectController:GetEquippedAbilities(): {string}
    local out = {}
    for _, abilityId in pairs(self._keybinds) do
        if abilityId then
            table.insert(out, abilityId)
        end
    end
    return out
end

function AspectController:IsOnCooldown(abilityId: string)
    local expiry = self._cooldowns[abilityId]
    return expiry and expiry > tick() or false
end

-- handle network events
NetworkProvider:RegisterClientEvent("AbilityDataSync", function(packet: NetworkTypes.AbilityDataSyncPacket)
    AspectController._cooldowns = packet.Cooldowns or {}
end)

NetworkProvider:RegisterClientEvent("AbilityCastResult", function(success, reason, abilityId, targetPos)
    if not success then
        warn("Ability cast failed:", reason)
    end
    if success and abilityId then
        -- start local cooldown as well
        local ability = AspectRegistry.Abilities[abilityId]
        if ability then
            AspectController._cooldowns[abilityId] = tick() + ability.Cooldown
        end
    end
end)

NetworkProvider:RegisterClientEvent("AspectAssigned", function(aspectId)
    -- cache aspect data (not complete profile, just id)
    AspectController._aspectData = {AspectId = aspectId, IsUnlocked = true, Branches = {Expression={Depth=0,ShardsInvested=0},Form={Depth=0,ShardsInvested=0},Communion={Depth=0,ShardsInvested=0}}, TotalShardsInvested=0}
end)

-- input binding
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local abilityId = AspectController._keybinds[input.KeyCode]
        if abilityId then
            if not AspectController:IsOnCooldown(abilityId) then
                local mouse = Players.LocalPlayer and Players.LocalPlayer:GetMouse()
                local pos = mouse and mouse.Hit and mouse.Hit.p
                NetworkProvider:FireServer("AbilityCastRequest", abilityId, pos)
            end
        end
    end
end)

-- project initialization functions
function AspectController:Init()
    print("[AspectController] Initialized")
    -- could read user settings for keybinds later
end

function AspectController:Start()
    print("[AspectController] Started")
end

return AspectController
