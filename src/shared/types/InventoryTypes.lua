--!strict
--[[
    Class: InventoryTypes
    Description: Type definitions for the custom inventory and equipment system
    Dependencies: None
]]

export type ItemRarity = "Common" | "Uncommon" | "Rare" | "Legendary" | "Mythic"

export type EquipmentSlotId = 
    "Weapon" 
    | "Armor" 
    | "Helmet" 
    | "Accessory1" 
    | "Accessory2"

export type InventoryItem = {
    Id: string,
    Name: string,
    Description: string,
    Rarity: ItemRarity,
    StackSize: number,
    Quantity: number,
    IconId: string,
    EquipSlot: EquipmentSlotId?,
    StatBonuses: {[string]: number}?,
    IsEquipped: boolean,
}

export type InventoryState = {
    Items: {InventoryItem},
    EquippedItems: {[EquipmentSlotId]: InventoryItem?},
    MaxSlots: number,
    UsedSlots: number,
}

export type InventorySyncPacket = {
    State: InventoryState,
}

export type EquipRequestPacket = {
    ItemId: string,
    SlotId: EquipmentSlotId,
}

export type EquipResultPacket = {
    Success: boolean,
    SlotId: EquipmentSlotId,
    Item: InventoryItem?,
    Reason: string?,
}

export type UnequipRequestPacket = {
    SlotId: EquipmentSlotId,
}

export type UnequipResultPacket = {
    Success: boolean,
    SlotId: EquipmentSlotId,
    Item: InventoryItem?,
    Reason: string?,
}

return {}
