--!strict
--[[
    InventoryController.lua

    Displays a simple inventory UI and handles user clicks to equip/use items.
    Depends on AspectController for equip requests and NetworkController for
    listening to InventorySync events (via AspectController update cache).

    Dependencies: NetworkController, AspectController, Utils
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local ItemTypes = require(ReplicatedStorage.Shared.types.ItemTypes) :: any

local localPlayer = Players.LocalPlayer

local InventoryController = {}
InventoryController._aspectController = nil :: any
InventoryController._gui = nil :: ScreenGui?

-- create or fetch the GUI container
local function _ensureGui()
    if InventoryController._gui then
        return InventoryController._gui
    end
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "InventoryUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Name = "InventoryFrame"
    frame.Size = UDim2.new(0, 200, 0, 100)
    frame.Position = UDim2.new(0.5, -100, 0.9, -50)
    frame.BackgroundTransparency = 0.5
    frame.Parent = screenGui

    InventoryController._gui = screenGui
    return screenGui
end

-- rebuild UI from inventory list
function InventoryController:RefreshUI()
    local gui = _ensureGui()
    local frame = gui:FindFirstChild("InventoryFrame") :: Frame
    if not frame then return end

    -- clear existing buttons
    for _, child in ipairs(frame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local inventory = self._aspectController and self._aspectController:GetInventory() or {}
    for i, item in ipairs(inventory) do
        local btn = Instance.new("TextButton")
        btn.Name = "ItemButton" .. i
        btn.Size = UDim2.new(0, 40, 0, 40)
        btn.Position = UDim2.new(0, (i-1)*45, 0, 0)
        btn.Text = item.Name or "?"
        btn.Parent = frame

        btn.MouseButton1Click:Connect(function()
            if self._aspectController then
                self._aspectController:RequestEquip(tostring(i), item.Id)
            end
        end)
    end
end

-- handler for inventory sync (called when AspectController updates its cache)
local function _onInventoryUpdated()
    InventoryController:RefreshUI()
end

function InventoryController:Init(dependencies: {[string]: any}?)
    print("[InventoryController] Initializing...")
    if dependencies then
        self._aspectController = dependencies.AspectController
    end

    -- register refresh callback when aspect controller inventory changes
    if self._aspectController then
        -- assume AspectController stores inventory in _inventory and we can poll
        -- for simplicity we'll connect to a heartbeat here and refresh on change
        local lastCount = 0
        game:GetService("RunService").Heartbeat:Connect(function()
            local inv = self._aspectController:GetInventory()
            if #inv ~= lastCount then
                lastCount = #inv
                _onInventoryUpdated()
            end
        end)
    end

    print("[InventoryController] Initialized")
end

function InventoryController:Start()
    print("[InventoryController] Started")
    -- initial draw
    self:RefreshUI()
end

return InventoryController
