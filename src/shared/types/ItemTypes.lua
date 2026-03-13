--!strict
--[[
    Class: ItemTypes
    Description: Shared type definitions for items stored in player inventory.
                 Initially used for AspectMove items and later other item categories.
    Dependencies: AspectTypes (for AspectId)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AspectTypes = require(ReplicatedStorage.Shared.types.AspectTypes) :: any

export type ItemId = string
export type ItemCategory = 
    "Abilities" 
    | "Tools" 
    | "TrainingGear" 
    | "Equipment" 
    | "Weapons" 
    | "Schematics" 
    | "QuestItems" 
    | "Consumables" 
    | "Relics" 
    | "Materials" 
    -- legacy types (kept for compatibility)
    | "AspectMove" | "Weapon" | "Armor" | "Accessory" | "Consumable" | "Quest"

export type Rarity = "Common" | "Uncommon" | "Rare" | "Legendary" | "Potion" | "Elemental"

export type ItemBase = {
    Id: ItemId,
    Name: string,
    Description: string,
    Category: ItemCategory,
    Rarity: Rarity,
    Cooldown: number?, -- for abilities
    Tags: {string}?,   -- e.g. { "Mantra", "Light Weapon", "Rare Talent" }
    Weight: number?,   -- optional for capacity checks
}

-- An inventory item that represents a castable Aspect ability.
-- It behaves like a "move" that can be equipped to a hotbar slot.
export type AspectMoveItem = ItemBase & {
    Category: "AspectMove",
    AbilityId: string,      -- matches AspectAbility.Id
    AspectId: AspectTypes.AspectId,
}

-- Standalone active/passive ability item — appears in inventory and can be activated directly.
export type AbilityItem = ItemBase & {
    Category: "Abilities",
    AbilityId: string,  -- matches ability module Id field in shared/abilities
}

export type WeaponItem = ItemBase & {
    Category: "Weapons",
    WeaponId: string,
}

export type Item = AspectMoveItem | AbilityItem | WeaponItem | TrainingToolItem

-- Training tool item that can be used to directly increase stats
export type TrainingToolItem = ItemBase & {
    Category: "Tools",
    TrainingToolId: string,  -- references a definition in TrainingToolService
    StatToIncrease: ProgressionTypes.StatName,
    Amount: number,          -- how many points to increase the stat by
}

-- runtime aliases to satisfy require() calls without building real objects
local _exports: any = {}
_exports.ItemId = ({} :: any) :: ItemId
_exports.ItemCategory = ({} :: any) :: ItemCategory
_exports.ItemBase = ({} :: any) :: ItemBase
_exports.AspectMoveItem = ({} :: any) :: AspectMoveItem
_exports.Item = ({} :: any) :: Item

return _exports
