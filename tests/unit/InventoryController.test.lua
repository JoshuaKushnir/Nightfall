--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InventoryController = require(ReplicatedStorage.Client.controllers.InventoryController)

-- stub AspectController and NetworkController
local fakeAspect = {
    _inventory = {},
    _equipped = {},
    GetInventory = function(self) return self._inventory end,
    RequestEquip = function() end,
    OnInventoryChanged = function(self, fn)
        -- store callback for test to call manually
        self._cb = fn
    end,
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
        {
            name = "Hotbar shows equipped slots",
            fn = function()
                fakeAspect._equipped = { ["1"] = {Name="Quick"}, ["3"]={Name="Strong"} }
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                local hotbar = pg.InventoryUI:FindFirstChild("HotbarRoot")
                assert(hotbar and #hotbar:GetChildren() == 8, "Hotbar should have 8 slots")
            end,
        },
        {
            name = "Inventory sync callback fires RefreshUI",
            fn = function()
                -- clear
                local player = game:GetService("Players").LocalPlayer
                local inv = player.PlayerGui:FindFirstChild("InventoryUI")
                if inv then inv:Destroy() end

                -- initial inventory empty
                fakeAspect._inventory = {}
                InventoryController:RefreshUI()
                -- now simulate server update
                fakeAspect._inventory = {{Name="X", Category="Abilities", Rarity="Common"}}
                if fakeAspect._cb then
                    fakeAspect._cb()
                end
                local pg = player:WaitForChild("PlayerGui")
                local scroll = pg.InventoryUI.InventoryRoot.Scroll
                assert(#scroll:GetChildren() > 0, "RefreshUI should run on callback")
            end,
        },
        {
            name = "ToggleOpen changes state and moves UI",
            fn = function()
                -- ensure gui exists
                InventoryController:RefreshUI()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui.InventoryUI
                local root = gui.InventoryRoot
                InventoryController:ToggleOpen()
                wait(0.3)
                assert(InventoryController._isOpen == false, "should be closed")
                assert(root.Position.X.Scale == 1 and root.Position.X.Offset > 0, "root should move right offscreen")
                -- hotbar still exists after closing
                local hotbar = gui:FindFirstChild("HotbarRoot")
                assert(hotbar, "hotbar should persist when inventory is closed")
                InventoryController:ToggleOpen()
                wait(0.3)
                assert(InventoryController._isOpen == true, "should be open")
            end,
        },
        {
            name = "Hint text mentions backquote key",
            fn = function()
                InventoryController:RefreshUI()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui.InventoryUI
                local hint = gui:FindFirstChild("Hint")
                assert(hint and string.find(hint.Text, "`"), "hint should mention backquote")
            end,
        },
    },
}

