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
                -- prepare a fake PlayerGui environment
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                -- clear existing
                local existing = pg:FindFirstChild("InventoryUI")
                if existing then existing:Destroy() end

                fakeAspect._inventory = {{Name="A"},{Name="B"}}
                InventoryController:RefreshUI()
                local gui = pg:FindFirstChild("InventoryUI")
                assert(gui, "ScreenGui not created")
                local frame = gui:FindFirstChild("InventoryFrame")
                assert(frame and #frame:GetChildren() >= 2, "Buttons not created")
            end,
        },
    },
}
