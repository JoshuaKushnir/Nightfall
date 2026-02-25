--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InventoryController = require(ReplicatedStorage.Client.controllers.InventoryController)

-- stub AspectController and NetworkController
local fakeAspect = {
    _inventory = {},
    GetInventory = function(self) return self._inventory end,
    RequestEquip = function() end,
}

local stubNet = {}

-- bootstrap
InventoryController:Init({AspectController = fakeAspect, NetworkController = stubNet})

return {
    name = "InventoryController Unit Tests",
    tests = {
        {
            name = "RefreshUI creates buttons for inventory items",
            fn = function()
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                local existing = pg:FindFirstChild("InventoryUI")
                if existing then existing:Destroy() end

                fakeAspect._inventory = {{Name="A", Category="Abilities", Rarity="Common"},{Name="B", Category="Tools", Rarity="Uncommon"}}
                InventoryController:RefreshUI()
                local gui = pg:FindFirstChild("InventoryUI")
                assert(gui, "ScreenGui not created")
                local scroll = gui:FindFirstChild("InventoryRoot"):FindFirstChild("Scroll")
                assert(scroll and #scroll:GetChildren() >= 2, "Buttons not created")
            end,
        },
        {
            name = "Search filters items",
            fn = function()
                fakeAspect._inventory = {{Name="Alpha", Category="Abilities", Rarity="Common"}, {Name="Beta", Category="Abilities", Rarity="Common"}}
                InventoryController._search = "alpha"
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                local scroll = pg.InventoryUI.InventoryRoot.Scroll
                local count = 0
                for _, child in ipairs(scroll:GetChildren()) do
                    if child.Name:match("Item_") then count += 1 end
                end
                assert(count == 1, "Search should hide other items")
            end,
        },
    },
}
