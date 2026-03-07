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

-- callbacks for when inventory/equipment updates arrive from server
AspectController._inventoryChangeListeners = {}

AspectController._keybinds = {} :: {[Enum.KeyCode]: string?}
AspectController._keybinds = {
    [Enum.KeyCode.Z] = nil,
    [Enum.KeyCode.X] = nil,
    [Enum.KeyCode.C] = nil,
    [Enum.KeyCode.V] = nil,
}

local ASPECT_CYCLE: {AspectTypes.AspectId?} = {
    "Ash", "Tide", "Ember", "Gale", "Void", nil,
}
local _cycleIndex = 0  -- starts before "Ash"; first G press → "Ash"


local _inputConnections = {}

local function _onKeyInput(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    local key = input.KeyCode

    if key == Enum.KeyCode.G then
        AspectController:_cycleAspect()
        return
    end

    local abilityId = AspectController._keybinds[key]
    if abilityId and not AspectController:IsOnCooldown(abilityId) then
        local mouse = localPlayer and localPlayer:GetMouse()
        local pos = mouse and mouse.Hit and mouse.Hit.p
        NetworkProvider:FireServer("AbilityCastRequest", {
            AbilityId = abilityId,
            TargetPosition = pos,
        })
    end
end

function AspectController:_cycleAspect()
    _cycleIndex = (_cycleIndex % #ASPECT_CYCLE) + 1
    local nextAspect = ASPECT_CYCLE[_cycleIndex]

    if NetworkController then
        NetworkController:SendToServer("SwitchAspectRequest", {
            AspectId = nextAspect,
        })
    end

    local label = nextAspect or "None"
    print(("[AspectController] Switching aspect → %s"):format(label))
end


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
    return expiry ~= nil and expiry > tick()
end


-- network event handlers will be registered during Init when dependencies arrive

-- we declare local functions so they can be used after Init
local function _registerHandlers()
    if not NetworkController then return end

    NetworkController:RegisterHandler("AbilityDataSync", function(packet)
        -- packet[abilityId] = remaining seconds (not absolute server timestamp).
        -- Reconstruct absolute expiry using the local client tick() epoch so that
        -- server/client tick() differences (~20,000 s in live games) don't inflate cooldowns.
        local now = tick()
        local cooldowns: {[string]: number} = {}
        for abilityId, remaining in pairs(packet or {}) do
            if remaining > 0 then
                cooldowns[abilityId] = now + remaining
            end
        end
        AspectController._cooldowns = cooldowns
    end)

    NetworkController:RegisterHandler("InventorySync", function(packet)
        AspectController._inventory = packet.Inventory or {}
        AspectController._equipped = packet.Equipped or {}
        -- notify listeners so UI can refresh immediately
        for _, fn in ipairs(AspectController._inventoryChangeListeners) do
            pcall(fn)
        end
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
function AspectController:OnInventoryChanged(callback: ()->())
    if type(callback) == "function" then
        table.insert(AspectController._inventoryChangeListeners, callback)
    end
end

function AspectController:Init(dependencies)
    print("[AspectController] Initializing...")
    if dependencies then
        NetworkController = dependencies.NetworkController
    end

    table.insert(_inputConnections,
        UserInputService.InputBegan:Connect(_onKeyInput)
    )

    if NetworkController then
        NetworkController:RegisterHandler("SwitchAspectResult", function(packet)
            if packet.Success then
                print(("[AspectController] Aspect switch confirmed → %s"):format(
                    tostring(packet.AspectId or "None")
                ))
            else
                warn(("[AspectController] Aspect switch failed: %s"):format(
                    tostring(packet.Reason)
                ))
                _cycleIndex = math.max(0, _cycleIndex - 1)
            end
        end)
    end

    _registerHandlers()
    print("[AspectController] Initialized")
end


function AspectController:Start()
    print("[AspectController] Started")
end

return AspectController
