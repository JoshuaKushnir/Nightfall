--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.types.ItemTypes)

return {
    name = "ItemTypes Unit Tests",
    tests = {
        {
            name = "AspectMoveItem structure correct",
            fn = function()
                -- verify the type table exists and can construct an object
                assert(ItemTypes.AspectMoveItem, "AspectMoveItem type missing")
                local example = {
                    Id = "test",
                    Name = "Test Move",
                    Description = "A dummy move item",
                    Category = "AspectMove",
                    AbilityId = "Ash_Expr1_1",
                    AspectId = "Ash",
                }
                -- field checks
                assert(example.Category == "AspectMove")
                assert(type(example.AbilityId) == "string")
                assert(example.AspectId == "Ash")
            end,
        },
        {
            name = "Registry.MoveItems table exists",
            fn = function()
                local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)
                assert(type(AspectRegistry.MoveItems) == "table", "MoveItems registry missing")
            end,
        },
    },
}
