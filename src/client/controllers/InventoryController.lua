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

-- open/closed state and hint
InventoryController._isOpen = true

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
    root.Size = UDim2.new(0, 300, 0, 400)
    -- place on right side, away from debug UI
    root.Position = UDim2.new(1, -310, 0.1, 0)  -- right side with 10px margin
    root.BackgroundTransparency = 0.2
    root.BackgroundColor3 = Color3.fromRGB(50,50,50)
    root.Parent = screenGui

    -- stats area at top
    local stats = Instance.new("Frame")
    stats.Name = "Stats"
    stats.Size = UDim2.new(1, -10, 0, 40)
    stats.Position = UDim2.new(0, 5, 0, 5)
    stats.BackgroundTransparency = 0.3
    stats.BackgroundColor3 = Color3.fromRGB(60,60,60)
    stats.Parent = root
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name = "StatsLabel"
    statsLabel.Size = UDim2.new(1,0,1,0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.TextColor3 = Color3.new(1,1,1)
    statsLabel.TextScaled = true
    statsLabel.Text = ""
    statsLabel.Parent = stats
    InventoryController._statsFrame = stats

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Scroll"
    scroll.Size = UDim2.new(1, -10, 1, -100) -- account for stats + search area
    scroll.Position = UDim2.new(0,5,0,50)
    scroll.CanvasSize = UDim2.new(0,0,0,0)
    scroll.ScrollBarThickness = 6
    scroll.Parent = root

    -- hotbar is separate so it stays visible when inventory is closed
    local hotbar = Instance.new("Frame")
    hotbar.Name = "HotbarRoot"
    hotbar.Size = UDim2.new(0, 360, 0, 40) -- 8 slots ×45
    hotbar.Position = UDim2.new(1, -370, 1, -50)
    hotbar.AnchorPoint = Vector2.new(0, 0) -- top-left remains relative to screen
    hotbar.BackgroundTransparency = 0.3
    hotbar.BackgroundColor3 = Color3.fromRGB(30,30,30)
    hotbar.Parent = screenGui

    InventoryController._hotbarFrame = hotbar

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

    -- hint for opening when closed
    local hint = Instance.new("TextLabel")
    hint.Name = "Hint"
    hint.Size = UDim2.new(0, 200, 0, 50)
    hint.Position = UDim2.new(1, -210, 0, 10)
    hint.Text = "Press ` to toggle inventory"
    hint.BackgroundTransparency = 0.5
    hint.TextColor3 = Color3.new(1,1,1)
    hint.TextScaled = true
    hint.Parent = screenGui
    hint.Visible = not InventoryController._isOpen

    InventoryController._gui = screenGui
    return screenGui
end

-- rebuild UI from inventory list
function InventoryController:RefreshUI()
    local gui = _ensureGui()
    local root = gui:FindFirstChild("InventoryRoot")
    if not root then return end
    local scroll = root:FindFirstChild("Scroll") :: ScrollingFrame
    if not scroll then return end

    -- update stats label
    if InventoryController._statsFrame then
        local items = # (self._aspectController and self._aspectController:GetInventory() or {})
        local equipped = 0
        for _,v in pairs(self._equipped or {}) do
            if v then equipped += 1 end
        end
        local lbl = InventoryController._statsFrame:FindFirstChild("StatsLabel")
        if lbl then
            lbl.Text = string.format("Items: %d  Equipped: %d", items, equipped)
        end
    end

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

    -- build hotbar (always visible, separate frame)
    local hotbar = gui:FindFirstChild("HotbarRoot")
    if hotbar then
        for _, child in ipairs(hotbar:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        local slots = {}
        for k,v in pairs(self._equipped) do
            slots[tonumber(k) or 0] = v
        end
        for idx=1,8 do
            local btn = Instance.new("TextButton")
            btn.Name = "HotbarSlot"..idx
            btn.Size = UDim2.new(0,40,0,40)
            btn.Position = UDim2.new(0, (idx-1)*45, 0, 0)
            btn.BackgroundColor3 = Color3.fromRGB(60,60,60)
            local item = slots[idx]
            btn.Text = item and item.Name or ""
            btn.TextScaled = true
            btn.Parent = hotbar
            btn.MouseButton1Click:Connect(function()
                if self._aspectController then
                    self._aspectController:RequestUnequip(tostring(idx))
                end
            end)
        end
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

    -- register callback for inventory updates
    if self._aspectController and self._aspectController.OnInventoryChanged then
        self._aspectController:OnInventoryChanged(function()
            _onInventoryUpdated()
        end)
    end

    -- listen for key to toggle
    local UserInputService = game:GetService("UserInputService")
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.BackQuote then
            self:ToggleOpen()
        end
    end)

    print("[InventoryController] Initialized")
end

function InventoryController:Start()
    print("[InventoryController] Started")
    -- initial draw
    self:RefreshUI()
end


function InventoryController:ToggleOpen()
    self._isOpen = not self._isOpen
    local gui = _ensureGui()
    local root = gui:FindFirstChild("InventoryRoot")
    if root then
        -- slide off to the right when closed
        local target = self._isOpen and UDim2.new(1, -310, 0.1, 0) or UDim2.new(1, 10, 0.1, 0)
        local tween = game:GetService("TweenService"):Create(root, TweenInfo.new(0.25), {Position = target})
        tween:Play()
    end
    local hint = gui:FindFirstChild("Hint")
    if hint then
        hint.Visible = not self._isOpen
    end
end

return InventoryController
