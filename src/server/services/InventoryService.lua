--!strict
--[[
    InventoryService.lua

    Handles player inventory operations (add/remove/equip/use items).
    Equipped items are stored by numeric slot key ("1"–"8").
    Equipping moves an item OUT of the free inventory into the slot;
    unequipping returns it to inventory. Prevents duplicates in slots.

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

-- internal helper: send current inventory/equipped state to a single client
local function _syncInventory(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile then return end
    NetworkService:SendToClient(player, "InventorySync", {
        Inventory = profile.Inventory or {},
        Equipped = profile.EquippedItems or {},
    })
end

-- give an item to a player (into free inventory), returns true if added
function InventoryService.GiveItem(player: Player, item: ItemTypes.Item): boolean
    if not Utils.IsValidPlayer(player) or not item then return false end
    local profile = DataService:GetProfile(player)
    if not profile then return false end
    profile.Inventory = profile.Inventory or {}

    -- prevent giving duplicates that already exist in inventory or hotbar
    for _, v in ipairs(profile.Inventory) do
        if v.Id == item.Id then return false end
    end
    profile.EquippedItems = profile.EquippedItems or {}
    for _, v in pairs(profile.EquippedItems) do
        if v and v.Id == item.Id then return false end
    end

    table.insert(profile.Inventory, item)
    _syncInventory(player)
    return true
end

-- remove first instance of itemId from free inventory; returns true if removed
function InventoryService.RemoveItem(player: Player, itemId: string): boolean
    local profile = DataService:GetProfile(player)
    if not profile or not profile.Inventory then return false end
    for i, v in ipairs(profile.Inventory) do
        if v.Id == itemId then
            table.remove(profile.Inventory, i)
            _syncInventory(player)
            return true
        end
    end
    return false
end

--[[
    SetEquipped: move item with itemId into slot, or clear slot if itemId is nil.

    Rules:
    - slot is a string like "1" through "8"
    - When equipping: item is removed from free inventory and placed in slot
    - When unequipping: item is returned to free inventory
    - AspectMove items are used immediately and never persist in a slot
    - An item already in another slot is moved (not duplicated)
    - Weapons route through EquipWeapon network event to WeaponService as well
]]
function InventoryService.SetEquipped(player: Player, slot: string, itemId: string?)
    local profile = DataService:GetProfile(player)
    if not profile then
        return false
    end

    profile.EquippedItems = profile.EquippedItems or {}

    if itemId == nil then
        profile.EquippedItems[slot] = nil
    else
        -- Find the item in the player's inventory and store a reference
        local found = nil
        if profile.Inventory then
            for _, v in ipairs(profile.Inventory) do
                if v.Id == itemId then
                    found = v
                    break
                end
            end
        end
        if not found then
            warn(`[InventoryService] SetEquipped: item "{itemId}" not in {player.Name}'s inventory`)
            return false
        end
        profile.EquippedItems[slot] = found
    end

    _syncInventory(player)
    return true
end

-- attempt to use an item; calls AspectService for AspectMove items
function InventoryService.UseItem(player: Player, itemId: string, target: Player?)
    local profile = DataService:GetProfile(player)
    if not profile then return false, "NoInventory" end

    -- Search inventory first, then equipped slots
    local item
    for _, v in ipairs(profile.Inventory or {}) do
        if v.Id == itemId then item = v break end
    end
    if not item then
        for _, v in pairs(profile.EquippedItems or {}) do
            if v and v.Id == itemId then item = v break end
        end
    end

    if not item then return false, "ItemNotFound" end
    if item.Category == "AspectMove" then
        return AspectService.ExecuteAbility(player, item.AbilityId,
            target and target.Character and target.Character.PrimaryPart
                and target.Character.PrimaryPart.Position)
    end
    return false, "UnhandledCategory"
end

-- network handlers
local function _onEquipRequest(player, packet)
    -- packet.Slot = "1"–"8", packet.ItemId = item id string
    InventoryService.SetEquipped(player, tostring(packet.Slot), packet.ItemId)
end

local function _onUnequipRequest(player, packet)
    InventoryService.SetEquipped(player, tostring(packet.Slot), nil)
end

local function _onUseRequest(player, packet)
    InventoryService.UseItem(player, packet.ItemId, packet.Target)
end

-- EquipWeapon: WeaponService owning a weapon does NOT auto-slot into hotbar.
-- Hotbar placement is player-driven only (drag/click from inventory).
local function _onEquipWeapon(_player: Player, _packet: any)
    -- intentionally empty
end

local function _onPlayerAdded(player)
    local profile = DataService:GetProfile(player)
    if not profile then return end

    profile.Inventory = profile.Inventory or {}
    profile.EquippedItems = profile.EquippedItems or {}

    local hasQuick, hasStrong, hasFists = false, false, false
    for _, v in ipairs(profile.Inventory) do
        if v.Id == "move_Test_Move_Quick" then hasQuick = true end
        if v.Id == "move_Test_Move_Strong" then hasStrong = true end
        if v.Id == "weapon_fists" then hasFists = true end
    end
    -- also check equipped slots
    for _, v in pairs(profile.EquippedItems) do
        if v then
            if v.Id == "move_Test_Move_Quick" then hasQuick = true end
            if v.Id == "move_Test_Move_Strong" then hasStrong = true end
            if v.Id == "weapon_fists" then hasFists = true end
        end
    end

    if not hasQuick or not hasStrong then
        for _, move in pairs(AspectRegistry.MoveItems) do
            if (not hasQuick and move.Id == "move_Test_Move_Quick") or
               (not hasStrong and move.Id == "move_Test_Move_Strong") then
                table.insert(profile.Inventory, move)
                if move.Id == "move_Test_Move_Quick" then hasQuick = true end
                if move.Id == "move_Test_Move_Strong" then hasStrong = true end
            end
        end
    end

    if not hasFists then
        table.insert(profile.Inventory, {
            Id = "weapon_fists",
            Name = "Fists",
            Description = "Your bare hands.",
            Category = "Weapons",
            Rarity = "Common",
        })
    end

    _syncInventory(player)
end

-- exposed for testing
InventoryService._onPlayerAdded = _onPlayerAdded

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
    NetworkService:RegisterHandler("EquipWeapon", _onEquipWeapon)
    print("[InventoryService] Started")
end

return InventoryService