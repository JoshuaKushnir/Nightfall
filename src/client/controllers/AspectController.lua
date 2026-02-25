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
local ItemTypes = require(ReplicatedStorage.Shared.types.ItemTypes) :: any
local NetworkTypes = require(ReplicatedStorage.Shared.types.NetworkTypes)

local localPlayer = Players.LocalPlayer

-- dependency references (filled in Init)
local NetworkController: any = nil

local AspectController = {}
AspectController._cooldowns = {} -- abilityId -> expiry tick
-- typed via cast rather than annotation to avoid parser error
AspectController._aspectData = nil :: AspectTypes.PlayerAspectData?
AspectController._inventory = {} :: {ItemTypes.Item}
AspectController._equipped = {} :: {[string]: ItemTypes.Item?}
AspectController._keybinds = {} :: {[Enum.KeyCode]: string?}
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

function AspectController:GetInventory(): {ItemTypes.Item}
    return self._inventory
end

function AspectController:RequestEquip(slot: string, itemId: string)
    if NetworkController then
        NetworkController:SendToServer("EquipItem", {Slot = slot, ItemId = itemId})
    end
end

function AspectController:RequestUnequip(slot: string)
    if NetworkController then
        NetworkController:SendToServer("UnequipItem", {Slot = slot})
    end
end

function AspectController:RequestUse(itemId: string, target: Player?)
    if NetworkController then
        NetworkController:SendToServer("UseItem", {ItemId = itemId, Target = target})
    end
end

function AspectController:IsOnCooldown(abilityId: string)
    local expiry = self._cooldowns[abilityId]
    return expiry and expiry > tick() or false
end

-- network event handlers will be registered during Init when dependencies arrive

-- we declare local functions so they can be used after Init
local function _registerHandlers()
    if not NetworkController then return end

    NetworkController:RegisterHandler("AbilityDataSync", function(packet)
        AspectController._cooldowns = packet or {}
    end)

    NetworkController:RegisterHandler("InventorySync", function(packet)
        AspectController._inventory = packet.Inventory or {}
        AspectController._equipped = packet.Equipped or {}
        warn("[AspectController] InventorySync received", #AspectController._inventory)
        for i, item in ipairs(AspectController._inventory) do
            warn(`   inv {i}: {item.Id}`)
        end
        for slot, item in pairs(AspectController._equipped) do
            warn(`   eq {slot}: {item and item.Id or "<empty>"}`)
        end
    end)

    NetworkController:RegisterHandler("AbilityCastResult", function(packet)
        local success = packet.Success
        local reason = packet.Reason
        local abilityId = packet.AbilityId
        local targetPos = packet.TargetPosition
        if not success then
            warn("Ability cast failed:", reason)
        end
        if success and abilityId then
            local ability = AspectRegistry.Abilities[abilityId]
            if ability then
                AspectController._cooldowns[abilityId] = tick() + ability.Cooldown
            end
        end
    end)

    NetworkController:RegisterHandler("AspectAssigned", function(packet)
        local aspectId = packet
        AspectController._aspectData = {AspectId = aspectId, IsUnlocked = true, Branches = {Expression={Depth=0,ShardsInvested=0},Form={Depth=0,ShardsInvested=0},Communion={Depth=0,ShardsInvested=0}}, TotalShardsInvested=0}
    end)
end

-- input binding
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local abilityId = AspectController._keybinds[input.KeyCode]
        if abilityId then
            if not AspectController:IsOnCooldown(abilityId) then
                local mouse = Players.LocalPlayer and Players.LocalPlayer:GetMouse()
                local pos = mouse and mouse.Hit and mouse.Hit.p
                NetworkProvider:FireServer("AbilityCastRequest", {AbilityId = abilityId, TargetPosition = pos})
            end
        end
    end
end)

-- project initialization functions
function AspectController:Init(dependencies: {[string]: any}?)
    print("[AspectController] Initializing...")
    if dependencies then
        NetworkController = dependencies.NetworkController
    end
    _registerHandlers()
    print("[AspectController] Initialized")
    -- could read user settings for keybinds later
end

function AspectController:Start()
    print("[AspectController] Started")
end

return AspectController
