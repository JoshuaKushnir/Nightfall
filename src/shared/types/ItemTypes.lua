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
export type ItemCategory = "AspectMove" | "Weapon" | "Armor" | "Accessory" | "Consumable" | "Quest"

export type ItemBase = {
    Id: ItemId,
    Name: string,
    Description: string,
    Category: ItemCategory,
}

-- An inventory item that represents a castable Aspect ability.
-- It behaves like a "move" that can be equipped to a hotbar slot.
export type AspectMoveItem = ItemBase & {
    Category: "AspectMove",
    AbilityId: string,      -- matches AspectAbility.Id
    AspectId: AspectTypes.AspectId,
}

-- Union of all item types; currently only AspectMoveItem.
export type Item = AspectMoveItem -- future expansions will add other unions

-- runtime aliases to satisfy require() calls without building real objects
local _exports: any = {}
_exports.ItemId = ({} :: any) :: ItemId
_exports.ItemCategory = ({} :: any) :: ItemCategory
_exports.ItemBase = ({} :: any) :: ItemBase
_exports.AspectMoveItem = ({} :: any) :: AspectMoveItem
_exports.Item = ({} :: any) :: Item

return _exports
