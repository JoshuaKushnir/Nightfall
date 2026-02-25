--!strict
--[[
    InventoryService.lua

    Handles player inventory operations (add/remove/equip/use items).
    Initially scoped to AspectMove items; later to general equipment/consumables.

    Dependencies: DataService, AspectService, NetworkProvider, NetworkService,
                  AspectRegistry, Utils
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local AspectService = require(script.Parent.AspectService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local NetworkService = require(script.Parent.NetworkService)
local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)

local ItemTypes = require(ReplicatedStorage.Shared.types.ItemTypes) :: any

local InventoryService = {}
InventoryService._initialized = false

-- internal helper: send current inventory to a single client
local function _syncInventory(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile then
        return
    end
    NetworkService:SendToClient(player, "InventorySync", {
        Inventory = profile.Inventory or {},
        Equipped = profile.EquippedItems or {},
    })
end

-- give an item to a player, returns true if added
function InventoryService.GiveItem(player: Player, item: ItemTypes.Item): boolean
    if not Utils.IsValidPlayer(player) or not item then
        return false
    end
    local profile = DataService:GetProfile(player)
    if not profile then
        return false
    end
    profile.Inventory = profile.Inventory or {}
    table.insert(profile.Inventory, item)
    _syncInventory(player)
    return true
end

-- remove first instance of itemId from inventory; returns true if removed
function InventoryService.RemoveItem(player: Player, itemId: string): boolean
    local profile = DataService:GetProfile(player)
    if not profile or not profile.Inventory then
        return false
    end
    for i, v in ipairs(profile.Inventory) do
        if v.Id == itemId then
            table.remove(profile.Inventory, i)
            _syncInventory(player)
            return true
        end
    end
    return false
end

-- equip/unequip an item into a slot; slot is arbitrary string (hotbar index etc)
function InventoryService.SetEquipped(player: Player, slot: string, itemId: string?)
    local profile = DataService:GetProfile(player)
    if not profile then
        return false
    end
    -- auto-use moves rather than persist them on slots
    if itemId then
        -- detect item in inventory
        local item
        if profile.Inventory then
            for _, v in ipairs(profile.Inventory) do
                if v.Id == itemId then
                    item = v
                    break
                end
            end
        end
        if item and item.Category == "AspectMove" then
            -- trigger use immediately and do not equip
            InventoryService.UseItem(player, itemId)
            return true
        end
    end

    profile.EquippedItems = profile.EquippedItems or {}
    if itemId == nil then
        profile.EquippedItems[slot] = nil
    else
        -- find object in inventory and store reference
        profile.EquippedItems[slot] = nil
        if profile.Inventory then
            for _, v in ipairs(profile.Inventory) do
                if v.Id == itemId then
                    profile.EquippedItems[slot] = v
                    break
                end
            end
        end
    end
    _syncInventory(player)
    return true
end

-- attempt to use an item; calls AspectService for AspectMove items
-- returns (boolean success, string? reason)
function InventoryService.UseItem(player: Player, itemId: string, target: Player?)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.Inventory then
        return false, "NoInventory"
    end
    local item
    for _, v in ipairs(profile.Inventory) do
        if v.Id == itemId then
            item = v
            break
        end
    end
    if not item then
        return false, "ItemNotFound"
    end
    if item.Category == "AspectMove" then
        -- forward to AspectService using stored ability id
        return AspectService.ExecuteAbility(player, item.AbilityId, target and target.Character and target.Character.PrimaryPart and target.Character.PrimaryPart.Position)
    end
    -- other categories not implemented yet
    return false, "UnhandledCategory"
end

-- network handlers
local function _onEquipRequest(player, packet)
    InventoryService.SetEquipped(player, packet.Slot, packet.ItemId)
end

local function _onUnequipRequest(player, packet)
    InventoryService.SetEquipped(player, packet.Slot, nil)
end

local function _onUseRequest(player, packet)
    InventoryService.UseItem(player, packet.ItemId, packet.Target)
end

local function _onPlayerAdded(player)
    local profile = DataService:GetProfile(player)
    if profile then
        profile.Inventory = profile.Inventory or {}
        -- ensure both test moves exist (add if missing)
        local hasQuick, hasStrong = false, false
        local hasFists = false
        for _, v in ipairs(profile.Inventory) do
            if v.Id == "move_Test_Move_Quick" then
                hasQuick = true
            elseif v.Id == "move_Test_Move_Strong" then
                hasStrong = true
            elseif v.Id == "weapon_fists" then
                hasFists = true
            end
        end
        if not hasQuick or not hasStrong then
            for _, move in pairs(AspectRegistry.MoveItems) do
                if (not hasQuick and move.Id == "move_Test_Move_Quick") or (not hasStrong and move.Id == "move_Test_Move_Strong") then
                    table.insert(profile.Inventory, move)
                    if move.Id == "move_Test_Move_Quick" then hasQuick = true end
                    if move.Id == "move_Test_Move_Strong" then hasStrong = true end
                end
            end
        end
        -- grant fists weapon if missing
        if not hasFists then
            table.insert(profile.Inventory, {
                Id = "weapon_fists",
                Name = "Fists",
                Description = "Your bare hands.",
                Category = "Weapons",
                Rarity = "Common",
            })
        end
    end
    _syncInventory(player)
end

function InventoryService:Init()
    if self._initialized then
        warn("[InventoryService] already initialized")
        return
    end
    print("[InventoryService] Initializing...")
    Players.PlayerAdded:Connect(_onPlayerAdded)
    self._initialized = true
    print("[InventoryService] Initialized")
end

function InventoryService:Start()
    print("[InventoryService] Starting...")
    NetworkService:RegisterHandler("EquipItem", _onEquipRequest)
    NetworkService:RegisterHandler("UnequipItem", _onUnequipRequest)
    NetworkService:RegisterHandler("UseItem", _onUseRequest)
    print("[InventoryService] Started")
end

return InventoryService
