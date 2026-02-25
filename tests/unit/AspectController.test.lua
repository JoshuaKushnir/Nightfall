--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

local AspectController = require(ReplicatedStorage.Client.controllers.AspectController)

-- setup stub NetworkController with registration mimic
local stubNet = {handlers = {}}
function stubNet:RegisterHandler(event, fn)
    self.handlers[event] = fn
end

-- bootstrap controller
if AspectController.Init then
    AspectController:Init({NetworkController = stubNet})
end
if AspectController.Start then
    AspectController:Start()
end

return {
    name = "AspectController Unit Tests",
    tests = {
        {
            name = "InventorySync updates local inventory",
            fn = function()
                stubNet.handlers["InventorySync"]({Inventory = {{Id = "item1"}}})
                local inv = AspectController:GetInventory()
                assert(#inv == 1 and inv[1].Id == "item1")
            end,
        },
        {
            name = "Request methods fire correct network events",
            fn = function()
                local calls = {}
                NetworkProvider.FireServer = function(_self, event, packet)
                    table.insert(calls, {event = event, packet = packet})
                end
                AspectController:RequestEquip("slot0", "itemX")
                AspectController:RequestUnequip("slot0")
                AspectController:RequestUse("itemX")
                assert(calls[1].event == "EquipItem" and calls[1].packet.Slot == "slot0")
                assert(calls[2].event == "UnequipItem")
                assert(calls[3].event == "UseItem" and calls[3].packet.ItemId == "itemX")
            end,
        },
    },
}
