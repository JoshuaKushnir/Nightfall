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
-- UI helpers
local CATEGORY_ORDER = {
    "Abilities","Tools","TrainingGear","Equipment","Weapons",
    "Schematics","QuestItems","Consumables","Relics","Materials",
}

local CATEGORY_DISPLAY = {
    Abilities = "Abilities",
    Tools = "Tools",
    TrainingGear = "Training Gear",
    Equipment = "Equipment",
    Weapons = "Weapons",
    Schematics = "Schematics",
    QuestItems = "Quest Items",
    Consumables = "Consumables",
    Relics = "Relics",
    Materials = "Materials",
}

local CATEGORY_COLOR = {
    Abilities = Color3.fromRGB(180,180,255),
    Tools = Color3.fromRGB(200,180,120),
    TrainingGear = Color3.fromRGB(160,200,120),
    Equipment = Color3.fromRGB(200,160,200),
    Weapons = Color3.fromRGB(220,180,180),
    Schematics = Color3.fromRGB(180,220,180),
    QuestItems = Color3.fromRGB(180,180,200),
    Consumables = Color3.fromRGB(200,200,120),
    Relics = Color3.fromRGB(120,180,220),
    Materials = Color3.fromRGB(200,200,200),
}

local RARITY_BORDER = {
    Common = Color3.fromRGB(128,128,128),
    Uncommon = Color3.fromRGB(200,200,0),
    Rare = Color3.fromRGB(200,0,0),
    Legendary = Color3.fromRGB(0,200,200),
    Potion = Color3.fromRGB(160,0,160),
    Elemental = Color3.fromRGB(128,128,128),
}

-- state for collapse
InventoryController._collapsed = {}
for _,cat in ipairs(CATEGORY_ORDER) do InventoryController._collapsed[cat] = false end

-- store last search
InventoryController._search = ""

local function _ensureGui()
    if InventoryController._gui then
        return InventoryController._gui
    end
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "InventoryUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

    local root = Instance.new("Frame")
    root.Name = "InventoryRoot"
    root.Size = UDim2.new(0, 400, 0, 300)
    root.Position = UDim2.new(0.5, -200, 0.5, -150)
    root.BackgroundTransparency = 0.2
    root.BackgroundColor3 = Color3.fromRGB(50,50,50)
    root.Parent = screenGui

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Scroll"
    scroll.Size = UDim2.new(1, -10, 1, -30)
    scroll.Position = UDim2.new(0,5,0,5)
    scroll.CanvasSize = UDim2.new(0,0,0,0)
    scroll.ScrollBarThickness = 6
    scroll.Parent = root

    local search = Instance.new("TextBox")
    search.Name = "SearchBox"
    search.PlaceholderText = "Search..."
    search.Size = UDim2.new(1, -10, 0, 20)
    search.Position = UDim2.new(0,5,1,-25)
    search.Text = ""
    search.Parent = root
    search:GetPropertyChangedSignal("Text"):Connect(function()
        InventoryController._search = string.lower(search.Text)
        InventoryController:RefreshUI()
    end)

    InventoryController._gui = screenGui
    return screenGui
end

-- rebuild UI from inventory list
function InventoryController:RefreshUI()
    local gui = _ensureGui()
    local scroll = gui:FindFirstChild("InventoryRoot"):FindFirstChild("Scroll") :: ScrollingFrame
    if not scroll then return end

    -- clear previous children
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local inventory = self._aspectController and self._aspectController:GetInventory() or {}
    -- apply search filter
    local filtered = {}
    for _, item in ipairs(inventory) do
        if InventoryController._search == "" or string.find(string.lower(item.Name or ""), InventoryController._search, 1, true) then
            table.insert(filtered, item)
        end
    end

    local y = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        -- gather items in category
        local catItems = {}
        for _, item in ipairs(filtered) do
            if item.Category == cat then
                table.insert(catItems, item)
            end
        end
        if #catItems > 0 then
            -- header
            local header = Instance.new("TextButton")
            header.Name = "Header_"..cat
            header.Size = UDim2.new(1,0,0,24)
            header.Position = UDim2.new(0,0,0,y)
            header.BackgroundColor3 = CATEGORY_COLOR[cat] or Color3.new(0.1,0.1,0.1)
            header.Text = CATEGORY_DISPLAY[cat] .. " ("..#catItems..")"
            header.TextXAlignment = Enum.TextXAlignment.Left
            header.Parent = scroll
            header.MouseButton1Click:Connect(function()
                InventoryController._collapsed[cat] = not InventoryController._collapsed[cat]
                InventoryController:RefreshUI()
            end)
            y = y + 24
            if not InventoryController._collapsed[cat] then
                for _, item in ipairs(catItems) do
                    local btn = Instance.new("TextButton")
                    btn.Name = "Item_"..item.Id
                    btn.Size = UDim2.new(1,-10,0,20)
                    btn.Position = UDim2.new(0,5,0,y)
                    btn.BackgroundColor3 = CATEGORY_COLOR[cat] or Color3.new(0.2,0.2,0.2)
                    btn.BorderColor3 = RARITY_BORDER[item.Rarity or "Common"] or Color3.new(1,1,1)
                    btn.Text = item.Name
                    btn.TextScaled = true
                    btn.Parent = scroll
                    btn.MouseButton1Click:Connect(function()
                        if self._aspectController then
                            self._aspectController:RequestEquip(item.Id,item.Id)
                        end
                    end)
                    y = y + 22
                end
            end
        end
    end
    scroll.CanvasSize = UDim2.new(0,0,y)
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
