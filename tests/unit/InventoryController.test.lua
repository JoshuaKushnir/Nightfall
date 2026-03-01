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

local stubNet = {sent = {}}
stubNet.SendToServer = function(self, name, pkt)
    table.insert(stubNet.sent, {name=name, pkt=pkt})
end
-- also stub NetworkProvider.FireServer so ability modules can use it
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
NetworkProvider.FireServer = function(self, name, pkt)
    table.insert(stubNet.sent, {name=name, pkt=pkt})
end

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
            name = "Hotbar shows equipped slots when open",
            fn = function()
                fakeAspect._equipped = { ["1"] = {Name="Quick"}, ["3"]={Name="Strong"} }
                -- simulate server sync via callback
                if fakeAspect._cb then fakeAspect._cb() end
                InventoryController._isOpen = true
                -- RefreshUI is invoked by the callback so no need to call directly
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                local hotbar = pg.InventoryUI:FindFirstChild("HotbarRoot")
                -- we expect exactly 8 TextButton slots to exist when open
                local btnCount = 0
                for _,c in ipairs(hotbar and hotbar:GetChildren() or {}) do
                    if c:IsA("TextButton") then btnCount += 1 end
                end
                assert(btnCount == 8, "Hotbar should have 8 slots when open")
            end,
        },
        {
            name = "Hotbar hides empties when closed",
            fn = function()
                fakeAspect._equipped = { ["1"] = {Name="Quick"}, ["3"]={Name="Strong"} }
                InventoryController._isOpen = false
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                local hotbar = pg.InventoryUI:FindFirstChild("HotbarRoot")
                local children = hotbar:GetChildren()
                -- should only have two buttons because two items
                local count=0
                for _,c in ipairs(children) do if c:IsA("TextButton") then count+=1 end end
                assert(count == 2, "Hotbar closed should only show filled slots")
            end,
        },
        {
            name = "Non-numeric equipped keys still populate hotbar",
            fn = function()
                -- simulate server sending equipment with non-numeric slot
                fakeAspect._equipped = { weapon_fists = {Name="Fists"} }
                if fakeAspect._cb then fakeAspect._cb() end
                InventoryController._isOpen = true
                local player = game:GetService("Players").LocalPlayer
                local pg = player:WaitForChild("PlayerGui")
                local hotbar = pg.InventoryUI:FindFirstChild("HotbarRoot")
                local found=false
                for _,c in ipairs(hotbar:GetChildren()) do
                    if c:IsA("TextButton") and c.Text == "Fists" then
                        found = true
                        break
                    end
                end
                assert(found, "hotbar should show item even if slot key is non-numeric")
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
            name = "Inventory items are square"
            ,fn = function()
                fakeAspect._inventory = {{Id="foo",Name="Foo",Category="Abilities",Rarity="Common"}}
                InventoryController:RefreshUI()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui.InventoryUI
                local btn = gui.InventoryUI.InventoryRoot.Scroll:FindFirstChild("Item_foo")
                assert(btn and btn.Size.X.Offset == btn.Size.Y.Offset, "Item button should be square")
            end,
        },
        {
            name = "Clicking weapon sends equip event",
            fn = function()
                stubNet.sent = {}
                fakeAspect._inventory = {{Id="fists",Name="Fists",Category="Weapons",Rarity="Common",WeaponId="fists"}}
                InventoryController._isOpen = true
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local gui = player.PlayerGui.InventoryUI
                local btn = gui.InventoryRoot.Scroll:FindFirstChild("Item_fists")
                assert(btn, "weapon button exists")
                btn.MouseButton1Click:Fire()
                wait(0.1)
                assert(#stubNet.sent == 1, "should send exactly one network event")
                assert(stubNet.sent[1].name == "EquipWeapon", "EquipWeapon should be sent")
                assert(type(stubNet.sent[1].pkt) == "table" and stubNet.sent[1].pkt.WeaponId == "fists", "payload should be table with WeaponId")
            end,
        },

        {
            name = "Clicking already equipped weapon sends unequip",
            fn = function()
                stubNet.sent = {}
                fakeAspect._inventory = {{Id="fists",Name="Fists",Category="Weapons",Rarity="Common",WeaponId="fists"}}
                -- fake WeaponController state
                WeaponController.GetEquipped = function() return "fists" end
                InventoryController._isOpen = true
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local gui = player.PlayerGui.InventoryUI
                local btn = gui.InventoryRoot.Scroll:FindFirstChild("Item_fists")
                assert(btn, "weapon button exists")
                btn.MouseButton1Click:Fire()
                wait(0.1)
                assert(#stubNet.sent == 1, "should send one event for toggle")
                assert(stubNet.sent[1].name == "UnequipWeapon", "UnequipWeapon should be sent")
            end,
        },
        {
            name = "Clicking hotbar weapon includes slot in payload",
            fn = function()
                stubNet.sent = {}
                -- equip item in slot 2 via AspectController cache
                fakeAspect._equipped = { ["2"] = {Name="Fists",Category="Weapons",Rarity="Common"} }
                if fakeAspect._cb then fakeAspect._cb() end
                InventoryController._isOpen = true
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local hotbar = player.PlayerGui.InventoryUI:FindFirstChild("HotbarRoot")
                local btn = hotbar and hotbar:FindFirstChild("HotbarSlot2")
                assert(btn, "hotbar slot exists")
                btn.MouseButton1Click:Fire()
                wait(0.1)
                assert(#stubNet.sent == 1)
                assert(stubNet.sent[1].name == "EquipWeapon")
                assert(type(stubNet.sent[1].pkt) == "table" and stubNet.sent[1].pkt.Slot == "2")
            end,
        },
        {
            name = "Hotbar ability activation sends cast request",
            fn = function()
                stubNet.sent = {}
                -- place an ability item in slot 1
                fakeAspect._equipped = { ["1"] = {Id="ability_IronWill",Category="Abilities",AbilityId="IronWill"} }
                if fakeAspect._cb then fakeAspect._cb() end
                InventoryController._isOpen = true
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local hotbar = player.PlayerGui.InventoryUI:FindFirstChild("HotbarRoot")
                local btn = hotbar and hotbar:FindFirstChild("HotbarSlot1")
                assert(btn, "ability slot exists")
                btn.MouseButton1Click:Fire()
                wait(0.1)
                assert(#stubNet.sent == 1, "should send cast request")
                assert(stubNet.sent[1].name == "AbilityCastRequest")
            end,
        },

        {
            name = "Closed hotbar click still includes slot",
            fn = function()
                stubNet.sent = {}
                fakeAspect._equipped = { ["3"] = {Name="Fists",Category="Weapons",Rarity="Common"} }
                if fakeAspect._cb then fakeAspect._cb() end
                InventoryController._isOpen = false
                InventoryController:RefreshUI()
                local player = game:GetService("Players").LocalPlayer
                local hotbar = player.PlayerGui.InventoryUI:FindFirstChild("HotbarRoot")
                local btn = hotbar and hotbar:FindFirstChild("HotbarSlot3")
                assert(btn, "hotbar slot exists when closed")
                btn.MouseButton1Click:Fire()
                wait(0.1)
                assert(#stubNet.sent == 1)
                assert(stubNet.sent[1].name == "EquipWeapon")
                assert(type(stubNet.sent[1].pkt) == "table" and stubNet.sent[1].pkt.Slot == "3")
            end,
        },

            end,
        },

        {
            name = "Drag weapon already owned only sends EquipItem",
            fn = function()
                stubNet.sent = {}
                fakeAspect._inventory = {{Id="fists",Name="Fists",Category="Weapons",Rarity="Common",WeaponId="fists"}}
                WeaponController.GetOwned = function() return "fists" end
                InventoryController._isOpen = true
                InventoryController:RefreshUI()
                local btn = game:GetService("Players").LocalPlayer.PlayerGui.InventoryUI.InventoryRoot.Scroll.Item_fists
                assert(btn, "weapon button exists for drag")
                InventoryController._debug_startDrag(btn, fakeAspect._inventory[1], "inventory")
                InventoryController._debug_finishDrag({item=fakeAspect._inventory[1],origin="inventory"}, Vector2.new(300, 800))
                wait(0.1)
                assert(#stubNet.sent == 1, "only one event should be sent")
                assert(stubNet.sent[1].name == "EquipItem", "should only reposition when already owned")
            end,
        },
        {
            name = "Drag new weapon sends EquipItem then EquipWeapon with slot",
            fn = function()
                stubNet.sent = {}
                fakeAspect._inventory = {{Id="axe",Name="Axe",Category="Weapons",Rarity="Common",WeaponId="axe"}}
                WeaponController.GetOwned = function() return nil end
                InventoryController._isOpen = true
                InventoryController:RefreshUI()
                local btn = game:GetService("Players").LocalPlayer.PlayerGui.InventoryUI.InventoryRoot.Scroll.Item_axe
                assert(btn, "weapon button exists for drag")
                InventoryController._debug_startDrag(btn, fakeAspect._inventory[1], "inventory")
                InventoryController._debug_finishDrag({item=fakeAspect._inventory[1],origin="inventory"}, Vector2.new(300, 800))
                wait(0.1)
                local sawEquipItem, sawEquipWeapon = false, false
                for _,e in ipairs(stubNet.sent) do
                    if e.name == "EquipItem" then sawEquipItem = true end
                    if e.name == "EquipWeapon" then
                        sawEquipWeapon = true
                        assert(type(e.pkt) == "table" and e.pkt.Slot ~= nil, "weapon payload should include slot")
                    end
                end
                assert(sawEquipItem and sawEquipWeapon, "both events should be sent")
            end,
        },
        {
            name = "Hint text mentions backquote key",
            fn = function()
                InventoryController:RefreshUI()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui.InventoryUI
                local hint = gui:FindFirstChild("OpenHint")
                assert(hint and string.find(hint.Text, "`"), "hint should mention backquote")
            end,
        },
    },
}

