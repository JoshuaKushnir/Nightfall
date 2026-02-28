--!strict
--[[
    Class: InventoryController
    Description: Client-side inventory UI, hotbar display, drag-and-drop,
                 equip/unequip logic, and hotbar number-key shortcuts.
    Dependencies: NetworkController, AspectController, Utils

    Behaviour spec:
        - Inventory panel hidden on spawn (toggle with ` or I)
        - Hotbar hidden when no items equipped AND inventory closed
        - Click item in inventory  → equip to first free hotbar slot
          - If already equipped    → unequip from its slot
          - Non-abilities: only ONE equipped at a time (equipping replaces)
          - Abilities: if something already equipped, auto-cast instead
        - Click hotbar slot        → equip/cast the item in that slot
        - Keys 1-8                 → equip/cast hotbar slot N
        - Drag inventory item onto hotbar slot → equip to that slot
        - Drag hotbar item off hotbar          → unequip from its slot
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local WeaponController = require(script.Parent.WeaponController)
local localPlayer = Players.LocalPlayer

-- ─── Constants ────────────────────────────────────────────────────────────────

local HOTBAR_SLOTS = 8
local SLOT_SIZE    = 46  -- px, includes 1px gap
local SLOT_BTN     = 42  -- px inner button
local SLOT_PAD     = 4   -- gap between slots
local INV_W        = 320
local INV_H        = 420

local CATEGORY_ORDER = {
    "Abilities","Weapons","Tools","Equipment","TrainingGear",
    "Schematics","QuestItems","Consumables","Relics","Materials",
}
local CATEGORY_DISPLAY: {[string]: string} = {
    Abilities="Abilities", Weapons="Weapons", Tools="Tools",
    Equipment="Equipment", TrainingGear="Training Gear",
    Schematics="Schematics", QuestItems="Quest Items",
    Consumables="Consumables", Relics="Relics", Materials="Materials",
}
local CATEGORY_COLOR: {[string]: Color3} = {
    Abilities    = Color3.fromRGB(180,180,255),
    Weapons      = Color3.fromRGB(220,180,180),
    Tools        = Color3.fromRGB(200,180,120),
    Equipment    = Color3.fromRGB(200,160,200),
    TrainingGear = Color3.fromRGB(160,200,120),
    Schematics   = Color3.fromRGB(180,220,180),
    QuestItems   = Color3.fromRGB(180,180,200),
    Consumables  = Color3.fromRGB(200,200,120),
    Relics       = Color3.fromRGB(120,180,220),
    Materials    = Color3.fromRGB(200,200,200),
}
local RARITY_BORDER: {[string]: Color3} = {
    Common    = Color3.fromRGB(128,128,128),
    Uncommon  = Color3.fromRGB(100,220,100),
    Rare      = Color3.fromRGB(80,120,220),
    Legendary = Color3.fromRGB(220,160,0),
    Potion    = Color3.fromRGB(160,0,160),
    Elemental = Color3.fromRGB(80,200,200),
}
local HOTBAR_KEYS = {
    Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
    Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
}

-- ─── Module ───────────────────────────────────────────────────────────────────

local InventoryController = {}
InventoryController._initialized = false

-- Dependencies (set in Init)
InventoryController._aspectController  = nil :: any
InventoryController._networkController = nil :: any

-- State
InventoryController._isOpen   = false           -- inventory panel open?
InventoryController._equipped = {} :: {[string]: any} -- slot → item  (string key = tostring(1..8))
InventoryController._inventory = {} :: {any}    -- flat item list from server
InventoryController._search   = ""
InventoryController._collapsed = {} :: {[string]: boolean}
for _, cat in ipairs(CATEGORY_ORDER) do
    InventoryController._collapsed[cat] = false
end

-- GUI references (created once)
InventoryController._gui        = nil :: ScreenGui?
InventoryController._invRoot    = nil :: Frame?
InventoryController._hotbarRoot = nil :: Frame?

-- Drag state
local _dragging: {
    ghost: Frame,
    item: any,
    origin: string, -- "inventory" | "hotbar"
    slot: number?,
    moveConn: RBXScriptConnection,
    upConn: RBXScriptConnection,
} | nil = nil

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function _isAbility(item: any): boolean
    return item and (item.Category == "Abilities" or item.Category == "AspectMove")
end

--- Find which slot (1-8) this item is currently equipped in, or nil.
local function _equippedSlot(self: any, itemId: string): number?
    for i = 1, HOTBAR_SLOTS do
        local equipped = self._equipped[tostring(i)]
        if equipped and equipped.Id == itemId then
            return i
        end
    end
    return nil
end

--- First free hotbar slot, or nil if all full.
local function _firstFreeSlot(self: any): number?
    for i = 1, HOTBAR_SLOTS do
        if not self._equipped[tostring(i)] then
            return i
        end
    end
    return nil
end

--- Is any non-ability item equipped?
local function _equippedNonAbilitySlot(self: any): number?
    for i = 1, HOTBAR_SLOTS do
        local item = self._equipped[tostring(i)]
        if item and not _isAbility(item) then
            return i
        end
    end
    return nil
end

--- Send equip request to server and update local cache optimistically.
local function _sendEquip(self: any, slot: number, item: any)
    self._equipped[tostring(slot)] = item
    if self._networkController then
        self._networkController:SendToServer("EquipItem", {
            Slot   = tostring(slot),
            ItemId = item.Id,
        })
        if item.Category == "Weapons" then
            self._networkController:SendToServer("EquipWeapon", {WeaponId = item.Id})
        end
    end
end

--- Send unequip request to server and update local cache optimistically.
local function _sendUnequip(self: any, slot: number)
    local item = self._equipped[tostring(slot)]
    self._equipped[tostring(slot)] = nil
    if self._networkController and item then
        self._networkController:SendToServer("UnequipItem", {Slot = tostring(slot)})
        if item.Category == "Weapons" then
            self._networkController:SendToServer("UnequipWeapon", {WeaponId = item.Id})
        end
    end
end

--- Cast / use the item in a given slot.
local function _castSlot(self: any, slot: number)
    local item = self._equipped[tostring(slot)]
    if not item then return end
    if self._networkController then
        if _isAbility(item) then
            self._networkController:SendToServer("AbilityCastRequest", {AbilityId = item.Id})
        elseif item.Category == "Weapons" then
            self._networkController:SendToServer("EquipWeapon", {WeaponId = item.Id})
        else
            self._networkController:SendToServer("UseItem", {Slot = tostring(slot), ItemId = item.Id})
        end
    end
end

-- ─── GUI construction ─────────────────────────────────────────────────────────

local function _makeSlotButton(parent: Instance, x: number, y: number, size: number): TextButton
    local btn = Instance.new("TextButton")
    btn.Size         = UDim2.fromOffset(size, size)
    btn.Position     = UDim2.fromOffset(x, y)
    btn.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
    btn.BorderSizePixel  = 2
    btn.BorderColor3     = Color3.fromRGB(90, 90, 100)
    btn.Text             = ""
    btn.TextScaled       = true
    btn.TextColor3       = Color3.new(1, 1, 1)
    btn.AutoButtonColor  = false
    btn.Parent = parent
    return btn
end

local function _ensureGui(self: any): ScreenGui
    if self._gui then
        return self._gui :: ScreenGui
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name         = "InventoryUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent       = localPlayer:WaitForChild("PlayerGui")

    -- ── Inventory panel (starts offscreen to the right) ──────────────────────
    local root = Instance.new("Frame")
    root.Name                  = "InventoryRoot"
    root.Size                  = UDim2.fromOffset(INV_W, INV_H)
    root.Position              = UDim2.new(1, 10, 0.1, 0)  -- offscreen (closed)
    root.BackgroundColor3      = Color3.fromRGB(30, 30, 38)
    root.BackgroundTransparency= 0.05
    root.BorderSizePixel       = 0
    root.Parent                = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = root

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name  = "TitleBar"
    titleBar.Size  = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    titleBar.BorderSizePixel  = 0
    titleBar.Parent = root
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size  = UDim2.new(1, -10, 1, 0)
    titleLabel.Position = UDim2.fromOffset(8, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text  = "INVENTORY"
    titleLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    titleLabel.TextSize   = 13
    titleLabel.Font       = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    -- Search box
    local searchBox = Instance.new("TextBox")
    searchBox.Name             = "SearchBox"
    searchBox.Size             = UDim2.new(1, -16, 0, 24)
    searchBox.Position         = UDim2.fromOffset(8, 36)
    searchBox.PlaceholderText  = "Search items…"
    searchBox.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    searchBox.TextColor3       = Color3.new(1, 1, 1)
    searchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
    searchBox.TextSize         = 12
    searchBox.Font             = Enum.Font.Gotham
    searchBox.ClearTextOnFocus = false
    searchBox.BorderSizePixel  = 0
    searchBox.Parent           = root
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 4)
    sc.Parent = searchBox

    -- Scroll frame for items
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name                = "Scroll"
    scroll.Size                = UDim2.new(1, -16, 1, -72)
    scroll.Position            = UDim2.fromOffset(8, 66)
    scroll.CanvasSize          = UDim2.fromOffset(0, 0)
    scroll.ScrollBarThickness  = 4
    scroll.ScrollBarImageColor3= Color3.fromRGB(100, 100, 120)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel     = 0
    scroll.Parent              = root

    -- ── Hotbar (separate, bottom-center, hidden by default) ──────────────────
    local hotbar = Instance.new("Frame")
    hotbar.Name                = "HotbarRoot"
    hotbar.AnchorPoint         = Vector2.new(0.5, 1)
    hotbar.Position            = UDim2.new(0.5, 0, 1, -8)
    hotbar.Size                = UDim2.fromOffset(0, SLOT_BTN + 22) -- width set dynamically
    hotbar.BackgroundTransparency = 1
    hotbar.Visible             = false  -- hidden until items arrive
    hotbar.Parent              = screenGui

    -- Hint label above hotbar (shown when inventory closed)
    local hint = Instance.new("TextLabel")
    hint.Name               = "OpenHint"
    hint.Size               = UDim2.fromOffset(220, 20)
    hint.AnchorPoint        = Vector2.new(0.5, 1)
    hint.Position           = UDim2.new(0.5, 0, 1, -60)
    hint.BackgroundTransparency = 1
    hint.Text               = "Press ` or I to open inventory"
    hint.TextColor3         = Color3.fromRGB(160, 160, 170)
    hint.TextSize           = 11
    hint.Font               = Enum.Font.Gotham
    hint.Visible            = false
    hint.Parent             = screenGui

    self._gui        = screenGui
    self._invRoot    = root
    self._hotbarRoot = hotbar

    -- Wire up search
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self._search = string.lower(searchBox.Text)
        self:RefreshUI()
    end)

    return screenGui
end

-- ─── Drag-and-drop ────────────────────────────────────────────────────────────

local function _finishDrag(self: any, mousePos: Vector3)
    if not _dragging then return end
    local drag = _dragging

    local hotbar = self._hotbarRoot :: Frame?
    if hotbar then
        local abs = hotbar.AbsolutePosition
        local sz  = hotbar.AbsoluteSize
        local lx  = mousePos.X - abs.X
        local ly  = mousePos.Y - abs.Y

        if lx >= 0 and ly >= 0 and lx <= sz.X and ly <= sz.Y then
            -- Dropped ON the hotbar
            local targetSlot = math.clamp(math.floor(lx / SLOT_SIZE) + 1, 1, HOTBAR_SLOTS)
            if drag.origin == "inventory" then
                -- Equip to target slot (unequip whatever was there first)
                if self._equipped[tostring(targetSlot)] then
                    _sendUnequip(self, targetSlot)
                end
                _sendEquip(self, targetSlot, drag.item)
            elseif drag.origin == "hotbar" and drag.slot then
                -- Swap slots
                local slotA = drag.slot
                local slotB = targetSlot
                if slotA ~= slotB then
                    local itemA = self._equipped[tostring(slotA)]
                    local itemB = self._equipped[tostring(slotB)]
                    self._equipped[tostring(slotA)] = itemB
                    self._equipped[tostring(slotB)] = itemA
                    if self._networkController then
                        -- Re-sync both slots
                        if itemA then _sendEquip(self, slotB, itemA) else _sendUnequip(self, slotB) end
                        if itemB then _sendEquip(self, slotA, itemB) else _sendUnequip(self, slotA) end
                    end
                end
            end
        else
            -- Dropped OFF the hotbar
            if drag.origin == "hotbar" and drag.slot then
                _sendUnequip(self, drag.slot)
            end
            -- Dropping inventory item outside hotbar = do nothing
        end
    end

    self:RefreshUI()
end

local function _startDrag(self: any, btn: GuiObject, item: any, origin: string, slot: number?)
    if _dragging then return end

    local ghost = Instance.new("Frame")
    ghost.Name              = "DragGhost"
    ghost.Size              = UDim2.fromOffset(SLOT_BTN, SLOT_BTN)
    ghost.BackgroundColor3  = CATEGORY_COLOR[item.Category] or Color3.fromRGB(80,80,90)
    ghost.BackgroundTransparency = 0.3
    ghost.BorderSizePixel   = 0
    ghost.ZIndex            = 1000
    ghost.AnchorPoint       = Vector2.new(0.5, 0.5)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1,1)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1,1,1)
    label.TextScaled = true
    label.Text = item.Name
    label.ZIndex = 1001
    label.Parent = ghost
    ghost.Parent = self._gui

    local mc: RBXScriptConnection
    local uc: RBXScriptConnection
    mc = UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then
            ghost.Position = UDim2.fromOffset(inp.Position.X, inp.Position.Y)
        end
    end)
    uc = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            mc:Disconnect()
            uc:Disconnect()
            ghost:Destroy()
            if _dragging then
                _finishDrag(self, inp.Position)
                _dragging = nil
            end
        end
    end)

    _dragging = {
        ghost    = ghost,
        item     = item,
        origin   = origin,
        slot     = slot,
        moveConn = mc,
        upConn   = uc,
    }
end

-- ─── Click handlers ───────────────────────────────────────────────────────────

--- Called when player clicks an item in the bag.
local function _onInventoryItemClick(self: any, item: any)
    local currentSlot = _equippedSlot(self, item.Id)

    if currentSlot then
        -- Already equipped → unequip
        _sendUnequip(self, currentSlot)
    elseif _isAbility(item) then
        -- Ability: if something already equipped, auto-cast; else equip
        local anyEquipped = false
        for i = 1, HOTBAR_SLOTS do
            if self._equipped[tostring(i)] then
                anyEquipped = true
                break
            end
        end

        if anyEquipped then
            -- Auto-cast the ability instead of equipping
            if self._networkController then
                self._networkController:SendToServer("AbilityCastRequest", {AbilityId = item.Id})
            end
            self:RefreshUI()
            return
        else
            -- Equip ability, but first remove any non-ability item
            local prevSlot = _equippedNonAbilitySlot(self)
            if prevSlot then
                _sendUnequip(self, prevSlot)
            end
            local slot = _firstFreeSlot(self) or 1
            _sendEquip(self, slot, item)
        end
    else
        -- Non-ability: only one may be equipped at a time
        local prevSlot = _equippedNonAbilitySlot(self)
        if prevSlot then
            _sendUnequip(self, prevSlot)
        end
        local slot = _firstFreeSlot(self) or 1
        _sendEquip(self, slot, item)
    end

    self:RefreshUI()
end

--- Called when player clicks a hotbar slot.
local function _onHotbarSlotClick(self: any, slot: number)
    local item = self._equipped[tostring(slot)]
    if not item then return end

    if _isAbility(item) then
        if self._networkController then
            self._networkController:SendToServer("AbilityCastRequest", {AbilityId = item.Id})
        end
    elseif item.Category == "Weapons" then
        -- Toggle weapon equip
        if self._networkController then
            self._networkController:SendToServer("EquipWeapon", {WeaponId = item.Id})
        end
    else
        if self._networkController then
            self._networkController:SendToServer("UseItem", {Slot = tostring(slot), ItemId = item.Id})
        end
    end
end

-- ─── UI Refresh ───────────────────────────────────────────────────────────────

function InventoryController:RefreshUI()
    local gui = _ensureGui(self)

    -- ── Inventory panel items ─────────────────────────────────────────────────
    local scroll = self._invRoot and self._invRoot:FindFirstChild("Scroll") :: ScrollingFrame?
    if scroll then
        for _, child in ipairs(scroll:GetChildren()) do
            child:Destroy()
        end

        local search = string.lower(self._search)
        local COLS   = 5
        local BTN    = 44
        local PAD    = 6
        local yOffset = PAD

        -- Group items by category
        local groups: {[string]: {any}} = {}
        for _, item in ipairs(self._inventory or {}) do
            local cat = item.Category or "Materials"
            if not groups[cat] then groups[cat] = {} end
            if search == "" or string.find(string.lower(item.Name or ""), search, 1, true) then
                table.insert(groups[cat], item)
            end
        end

        for _, cat in ipairs(CATEGORY_ORDER) do
            local items = groups[cat]
            if not items or #items == 0 then continue end

            -- Category header (toggle collapse)
            local header = Instance.new("TextButton")
            header.Size  = UDim2.new(1, -PAD, 0, 22)
            header.Position = UDim2.fromOffset(PAD/2, yOffset)
            header.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
            header.BorderSizePixel = 0
            header.TextColor3 = CATEGORY_COLOR[cat] or Color3.new(1,1,1)
            header.Text  = (self._collapsed[cat] and "▶ " or "▼ ") .. (CATEGORY_DISPLAY[cat] or cat)
            header.TextSize = 11
            header.Font  = Enum.Font.GothamBold
            header.TextXAlignment = Enum.TextXAlignment.Left
            header.Parent = scroll
            yOffset += 22 + 4

            header.MouseButton1Click:Connect(function()
                self._collapsed[cat] = not self._collapsed[cat]
                self:RefreshUI()
            end)

            if self._collapsed[cat] then continue end

            -- Item grid
            local col = 0
            local row = 0
            for _, item in ipairs(items) do
                local isEquipped = _equippedSlot(self, item.Id) ~= nil
                local btn = Instance.new("TextButton")
                btn.Name = "Item_" .. (item.Id or item.Name or "?")
                btn.Size = UDim2.fromOffset(BTN, BTN)
                btn.Position = UDim2.fromOffset(PAD/2 + col * (BTN + PAD), yOffset + row * (BTN + PAD))
                btn.BackgroundColor3 = isEquipped
                    and Color3.fromRGB(70, 100, 70)
                    or (CATEGORY_COLOR[cat] and Color3.fromRGB(
                        math.floor(CATEGORY_COLOR[cat].R * 80),
                        math.floor(CATEGORY_COLOR[cat].G * 80),
                        math.floor(CATEGORY_COLOR[cat].B * 80)
                    ) or Color3.fromRGB(55,55,65))
                btn.BorderSizePixel = 2
                btn.BorderColor3 = (item.Rarity and RARITY_BORDER[item.Rarity]) or RARITY_BORDER["Common"]
                btn.TextColor3 = Color3.new(1,1,1)
                btn.TextScaled = true
                btn.Text = item.Name or "?"
                btn.Parent = scroll

                -- Equipped indicator
                if isEquipped then
                    local dot = Instance.new("Frame")
                    dot.Size = UDim2.fromOffset(6,6)
                    dot.Position = UDim2.new(1,-7,0,1)
                    dot.BackgroundColor3 = Color3.fromRGB(80,255,80)
                    dot.BorderSizePixel = 0
                    dot.ZIndex = btn.ZIndex + 1
                    local dotCorner = Instance.new("UICorner")
                    dotCorner.CornerRadius = UDim.new(1,0)
                    dotCorner.Parent = dot
                    dot.Parent = btn
                end

                btn.MouseButton1Click:Connect(function()
                    _onInventoryItemClick(self, item)
                end)
                btn.InputBegan:Connect(function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                        _startDrag(self, btn, item, "inventory", nil)
                    end
                end)

                col += 1
                if col >= COLS then
                    col = 0
                    row += 1
                end
            end

            local rows = math.max(1, math.ceil(#items / COLS))
            yOffset += rows * (BTN + PAD) + 8
        end

        scroll.CanvasSize = UDim2.fromOffset(0, yOffset + PAD)
    end

    -- ── Hotbar ────────────────────────────────────────────────────────────────
    local hotbar = self._hotbarRoot :: Frame?
    local hasAnyEquipped = false
    local filledSlots: {[number]: any} = {}
    if hotbar then
        -- Destroy old slot buttons
        for _, child in ipairs(hotbar:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("Frame") then
                child:Destroy()
            end
        end

        -- Count filled slots
        for i = 1, HOTBAR_SLOTS do
            local item = self._equipped[tostring(i)]
            if item then filledSlots[i] = item end
        end

        hasAnyEquipped = next(filledSlots) ~= nil

        if self._isOpen then
            -- Show all 8 slots
            local totalW = HOTBAR_SLOTS * SLOT_SIZE
            hotbar.Size    = UDim2.fromOffset(totalW, SLOT_BTN + 22)
            hotbar.Visible = true

            for i = 1, HOTBAR_SLOTS do
                local item = self._equipped[tostring(i)]
                local x = (i - 1) * SLOT_SIZE

                -- Slot background
                local slotBg = Instance.new("Frame")
                slotBg.Size = UDim2.fromOffset(SLOT_BTN, SLOT_BTN)
                slotBg.Position = UDim2.fromOffset(x, 0)
                slotBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
                slotBg.BorderSizePixel = 1
                slotBg.BorderColor3 = Color3.fromRGB(80, 80, 95)
                slotBg.Parent = hotbar

                local btn = _makeSlotButton(hotbar, x, 0, SLOT_BTN)
                btn.Name = "HotbarSlot" .. tostring(i)
                btn.BackgroundTransparency = 1
                btn.ZIndex = slotBg.ZIndex + 1
                if item then
                    btn.Text = item.Name
                    btn.BackgroundColor3 = CATEGORY_COLOR[item.Category] or Color3.fromRGB(60,60,75)
                    btn.BackgroundTransparency = 0.3
                end

                -- Slot number label
                local numLabel = Instance.new("TextLabel")
                numLabel.Size  = UDim2.fromOffset(12, 12)
                numLabel.Position = UDim2.fromOffset(x + 2, SLOT_BTN + 2)
                numLabel.BackgroundTransparency = 1
                numLabel.TextColor3 = Color3.fromRGB(160,160,170)
                numLabel.TextSize   = 10
                numLabel.Font       = Enum.Font.Gotham
                numLabel.Text       = tostring(i)
                numLabel.Parent     = hotbar

                local capturedSlot = i
                local capturedItem = item
                btn.MouseButton1Click:Connect(function()
                    if capturedItem then
                        _onHotbarSlotClick(self, capturedSlot)
                    end
                end)
                if capturedItem then
                    btn.InputBegan:Connect(function(inp)
                        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                            _startDrag(self, btn, capturedItem, "hotbar", capturedSlot)
                        end
                    end)
                end
            end
        else
            -- Inventory closed: only show filled slots, compactly
            if not hasAnyEquipped then
                hotbar.Visible = false
            else
                local count = 0
                for _ in pairs(filledSlots) do count += 1 end
                local totalW = count * SLOT_SIZE
                hotbar.Size    = UDim2.fromOffset(totalW, SLOT_BTN + 22)
                hotbar.Visible = true

                local xi = 0
                for i = 1, HOTBAR_SLOTS do
                    local item = filledSlots[i]
                    if not item then continue end

                    local slotBg = Instance.new("Frame")
                    slotBg.Size = UDim2.fromOffset(SLOT_BTN, SLOT_BTN)
                    slotBg.Position = UDim2.fromOffset(xi, 0)
                    slotBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
                    slotBg.BorderSizePixel  = 1
                    slotBg.BorderColor3     = Color3.fromRGB(80, 80, 95)
                    slotBg.Parent           = hotbar

                    local btn = _makeSlotButton(hotbar, xi, 0, SLOT_BTN)
                    btn.Name = "HotbarSlot" .. tostring(i)
                    btn.Text = item.Name
                    btn.BackgroundColor3 = CATEGORY_COLOR[item.Category] or Color3.fromRGB(60,60,75)
                    btn.BackgroundTransparency = 0.3
                    btn.ZIndex = slotBg.ZIndex + 1

                    local numLabel = Instance.new("TextLabel")
                    numLabel.Size  = UDim2.fromOffset(12, 12)
                    numLabel.Position = UDim2.fromOffset(xi + 2, SLOT_BTN + 2)
                    numLabel.BackgroundTransparency = 1
                    numLabel.TextColor3 = Color3.fromRGB(160,160,170)
                    numLabel.TextSize   = 10
                    numLabel.Font       = Enum.Font.Gotham
                    numLabel.Text       = tostring(i)
                    numLabel.Parent     = hotbar

                    local capturedSlot = i
                    local capturedItem = item
                    btn.MouseButton1Click:Connect(function()
                        _onHotbarSlotClick(self, capturedSlot)
                    end)
                    btn.InputBegan:Connect(function(inp)
                        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                            _startDrag(self, btn, capturedItem, "hotbar", capturedSlot)
                        end
                    end)

                    xi += SLOT_SIZE
                end
            end
        end
    end

    -- Hint label visibility
    local hint = self._gui and (self._gui :: ScreenGui):FindFirstChild("OpenHint") :: TextLabel?
    if hint then
        hint.Visible = not self._isOpen and not hasAnyEquipped
    end
end

-- ─── Toggle ───────────────────────────────────────────────────────────────────

function InventoryController:ToggleOpen()
    self._isOpen = not self._isOpen
    local root = self._invRoot :: Frame?
    if root then
        -- Slide in from right when open, slide out to right when closed
        local targetPos = self._isOpen
            and UDim2.new(1, -(INV_W + 10), 0.1, 0)
            or  UDim2.new(1, 10, 0.1, 0)
        TweenService:Create(root, TweenInfo.new(0.2, Enum.EasingStyle.Quart), {Position = targetPos}):Play()
    end
    self:RefreshUI()
end

-- ─── Init / Start ─────────────────────────────────────────────────────────────

function InventoryController:Init(dependencies: {[string]: any}?)
    if self._initialized then return end
    print("[InventoryController] Initializing...")

    if dependencies then
        self._aspectController  = dependencies.AspectController
        self._networkController = dependencies.NetworkController
    end

    -- Subscribe to inventory updates from server
    if self._aspectController and self._aspectController.OnInventoryChanged then
        self._aspectController:OnInventoryChanged(function()
            -- Refresh inventory list and equipped from AspectController cache
            if self._aspectController._inventory then
                self._inventory = self._aspectController._inventory
            end
            if self._aspectController._equipped then
                self._equipped = self._aspectController._equipped
            end
            self:RefreshUI()
        end)
    end

    -- Listen to InventorySync directly from NetworkController if available
    if self._networkController and self._networkController.OnEvent then
        self._networkController:OnEvent("InventorySync", function(packet)
            if packet.Inventory then self._inventory = packet.Inventory end
            if packet.Equipped  then
                -- Convert server equipped table format to our local format
                self._equipped = {}
                for slot, item in pairs(packet.Equipped) do
                    self._equipped[tostring(slot)] = item
                end
            end
            self:RefreshUI()
        end)
    end

    -- Hotbar number keys (1–8)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        for i, keyCode in ipairs(HOTBAR_KEYS) do
            if input.KeyCode == keyCode then
                _castSlot(self, i)
                return
            end
        end
    end)

    -- Inventory toggle keys (` and I)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        local kc = input.KeyCode
        local isBacktick = kc == Enum.KeyCode.Backquote
            or (kc == Enum.KeyCode.Unknown
                and input.UserInputType == Enum.UserInputType.Keyboard
                and input.Character == "`")
        if isBacktick or kc == Enum.KeyCode.I then
            self:ToggleOpen()
        end
    end)

    self._initialized = true
    print("[InventoryController] Initialized")
end

function InventoryController:Start()
    print("[InventoryController] Started")
    _ensureGui(self)
    -- Initial state: closed, hotbar hidden
    self._isOpen = false
    self:RefreshUI()
end

return InventoryController