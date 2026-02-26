--!strict
--[[
    InventoryController.lua — Deepwoken-style inventory + hotbar

    INTERACTION RULES:
    ─ Inventory item (non-ability) left-click → equip to first empty hotbar slot
    ─ Inventory item (ability) left-click     → nothing (drag-only)
    ─ Any inventory item drag → equip to dropped slot
    ─ Hotbar slot left-click (filled)  → UNEQUIP back to inventory
    ─ Hotbar slot left-click (ability) → USE ability (does NOT unequip)
    ─ Hotbar slot drag to other slot   → move/swap
    ─ Hotbar slot drag to outside      → unequip
    ─ Active (held) weapon slot shows white glow/outline

    BUG FIXES vs prev version:
    ─ WeaponService prefix: strip "weapon_" before sending EquipWeapon/guard check
    ─ UnequipWeapon never called from here (removes ownership); un-hold is local only
    ─ EquipWeapon guard uses stripped registryId, not raw itemId
    ─ Left-click hotbar = unequip for non-ability items
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local InventoryController = {}
InventoryController._aspectController  = nil :: any
InventoryController._networkController = nil :: any
InventoryController._gui               = nil :: ScreenGui?
InventoryController._isOpen            = true
InventoryController._collapsed         = {} :: {[string]: boolean}
InventoryController._search            = ""
InventoryController._statsFrame        = nil :: Frame?

-- ─── Constants ────────────────────────────────────────────────────────────────

local CATEGORY_ORDER = {
    "AspectMove", "Weapons", "Equipment", "Tools", "TrainingGear",
    "Consumables", "Relics", "Schematics", "QuestItems", "Materials",
}
local CATEGORY_DISPLAY = {
    AspectMove="Abilities", Weapons="Weapons", Equipment="Equipment",
    Tools="Tools", TrainingGear="Training Gear", Consumables="Consumables",
    Relics="Relics", Schematics="Schematics", QuestItems="Quest Items",
    Materials="Materials",
}
-- Dark muted tile colours per category (Deepwoken feel)
local CATEGORY_BG: {[string]: Color3} = {
    AspectMove   = Color3.fromRGB(42, 38, 68),
    Weapons      = Color3.fromRGB(62, 34, 34),
    Equipment    = Color3.fromRGB(36, 52, 62),
    Tools        = Color3.fromRGB(52, 48, 32),
    TrainingGear = Color3.fromRGB(36, 58, 38),
    Consumables  = Color3.fromRGB(58, 48, 28),
    Relics       = Color3.fromRGB(32, 42, 62),
    Schematics   = Color3.fromRGB(36, 54, 44),
    QuestItems   = Color3.fromRGB(42, 42, 52),
    Materials    = Color3.fromRGB(48, 48, 48),
}
-- Rarity outline colours (UIStroke)
local RARITY_STROKE: {[string]: Color3} = {
    Common    = Color3.fromRGB(110, 110, 110),
    Uncommon  = Color3.fromRGB(80,  190,  60),
    Rare      = Color3.fromRGB(60,  130, 220),
    Legendary = Color3.fromRGB(210, 150,  20),
    Potion    = Color3.fromRGB(170,  70, 200),
    Elemental = Color3.fromRGB(60,  200, 200),
}

local HOTBAR_SIZE    = 8
local SLOT_PX        = 48
local SLOT_PAD       = 6
local DRAG_THRESHOLD = 8  -- px movement before a press becomes a drag

-- Held-weapon active glow
local ACTIVE_STROKE_COLOR = Color3.fromRGB(255, 248, 180)
local ACTIVE_BG_TINT      = Color3.fromRGB(255, 255, 200)

for _, cat in ipairs(CATEGORY_ORDER) do
    InventoryController._collapsed[cat] = false
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- WeaponRegistry keys are bare ("fists"), but item IDs may have "weapon_" prefix.
-- Always strip before talking to WeaponService.
local function _toRegistryId(itemId: string): string
    return (itemId:gsub("^weapon_", ""))
end

local function _getEquipped(): {[string]: any}
    local ac = InventoryController._aspectController
    return (ac and ac._equipped) or {}
end

local function _equippedIdSet(): {[string]: boolean}
    local s = {}
    for _, v in pairs(_getEquipped()) do
        if v then s[v.Id] = true end
    end
    return s
end

local function _findItemById(id: string): any
    local ac  = InventoryController._aspectController
    local inv = (ac and ac:GetInventory()) or {}
    for _, v in ipairs(inv) do if v.Id == id then return v end end
    for _, v in pairs(_getEquipped()) do if v and v.Id == id then return v end end
    return nil
end

-- WeaponId of the tool currently held in Character (nil if none held)
local function _heldWeaponRegistryId(): string?
    local char = Players.LocalPlayer.Character
    if not char then return nil end
    for _, c in char:GetChildren() do
        if c:IsA("Tool") then
            local w = c:GetAttribute("WeaponId")
            if w then return w :: string end
        end
    end
    return nil
end

local function _makeCorner(p: Instance, r: number)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = p
end

local function _makeStroke(p: Instance, thickness: number, color: Color3): UIStroke
    local s = Instance.new("UIStroke")
    s.Thickness       = thickness
    s.Color           = color
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent          = p
    return s
end

-- ─── Network helpers ──────────────────────────────────────────────────────────

local function _net(): any
    return InventoryController._networkController
end

-- Slot an item into a hotbar position.
-- For weapons: fires EquipWeapon with STRIPPED registry id, guarded against
-- duplicate equip using the same stripped id for comparison.
local function _sendEquipItem(slot: number, itemId: string)
    if not _net() then return end
    _net():SendToServer("EquipItem", { Slot = tostring(slot), ItemId = itemId })
    local item = _findItemById(itemId)
    if item and item.Category == "Weapons" then
        local regId = _toRegistryId(itemId)
        local char  = Players.LocalPlayer.Character
        -- Compare stripped id against character attribute (server sets bare "fists", not "weapon_fists")
        local currentAttr = char and char:GetAttribute("EquippedWeapon")
        if currentAttr ~= regId then
            _net():SendToServer("EquipWeapon", { WeaponId = regId, Slot = tostring(slot) })
        end
    end
end

-- Remove an item from a hotbar slot → returns it to inventory.
-- For weapons: we DO NOT send UnequipWeapon (that destroys ownership).
-- We only un-hold locally (move tool from Character → Backpack).
local function _sendUnequipItem(slot: number)
    if not _net() then return end
    local item = _getEquipped()[tostring(slot)]
    _net():SendToServer("UnequipItem", { Slot = tostring(slot) })
    -- Un-hold if this weapon is currently physically held
    if item and item.Category == "Weapons" then
        local regId = _toRegistryId(item.Id)
        if _heldWeaponRegistryId() == regId then
            local char = Players.LocalPlayer.Character
            local bp   = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
            if char and bp then
                for _, c in char:GetChildren() do
                    if c:IsA("Tool") and c:GetAttribute("WeaponId") == regId then
                        c.Parent = bp
                        break
                    end
                end
            end
        end
    end
end

-- Fire an ability server-side without touching the hotbar slot.
local function _useAbility(itemId: string)
    if not _net() then return end
    _net():SendToServer("UseItem", { ItemId = itemId })
end

-- Move tool from Backpack → Character (hold/wield it).
local function _holdWeapon(itemId: string)
    local regId = _toRegistryId(itemId)
    local char  = Players.LocalPlayer.Character
    if not char then return end
    for _, c in char:GetChildren() do
        if c:IsA("Tool") and c:GetAttribute("WeaponId") == regId then return end -- already held
    end
    local bp = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, c in bp:GetChildren() do
            if c:IsA("Tool") and c:GetAttribute("WeaponId") == regId then
                c.Parent = char; return
            end
        end
    end
end

-- Un-hold: move tool from Character → Backpack (sheathe without removing ownership).
local function _unholdWeapon(itemId: string)
    local regId = _toRegistryId(itemId)
    local char  = Players.LocalPlayer.Character
    local bp    = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
    if not char or not bp then return end
    for _, c in char:GetChildren() do
        if c:IsA("Tool") and c:GetAttribute("WeaponId") == regId then
            c.Parent = bp; return
        end
    end
end

-- ─── Drag system ──────────────────────────────────────────────────────────────

local dragging: {button: TextButton, item: any, origin: string, slot: number?}? = nil

local function _finishDrag(drag: typeof(dragging), mousePos: Vector2)
    if not drag then return end
    local hotbar = InventoryController._gui
        and (InventoryController._gui :: ScreenGui):FindFirstChild("HotbarRoot") :: Frame?
    if hotbar then
        local lx = mousePos.X - hotbar.AbsolutePosition.X
        local ly = mousePos.Y - hotbar.AbsolutePosition.Y
        if lx >= 0 and ly >= 0 and lx <= hotbar.AbsoluteSize.X and ly <= hotbar.AbsoluteSize.Y then
            local idx = math.clamp(math.floor(lx / (SLOT_PX + SLOT_PAD)) + 1, 1, HOTBAR_SIZE)
            if drag.origin == "inventory" then
                _sendEquipItem(idx, drag.item.Id)
            elseif drag.origin == "hotbar" and drag.slot and drag.slot ~= idx then
                _sendEquipItem(idx, drag.item.Id)
            end
            return
        end
    end
    -- Dropped outside hotbar = unequip
    if drag.origin == "hotbar" and drag.slot then
        _sendUnequipItem(drag.slot)
    end
end

local function _launchGhost(btn: TextButton, item: any, origin: string, slot: number?, pos: Vector2)
    if dragging then return end
    dragging = { button = btn, item = item, origin = origin, slot = slot }
    local ghost = btn:Clone() :: TextButton
    ghost.Name                  = "DragGhost"
    ghost.Parent                = InventoryController._gui
    ghost.ZIndex                = 1000
    ghost.AnchorPoint           = Vector2.new(0.5, 0.5)
    ghost.BackgroundTransparency = 0.35
    ghost.Size                  = UDim2.new(0, SLOT_PX, 0, SLOT_PX)
    ghost.Position              = UDim2.new(0, pos.X, 0, pos.Y)

    local mc: RBXScriptConnection
    local uc: RBXScriptConnection
    mc = UserInputService.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then
            ghost.Position = UDim2.new(0, i.Position.X, 0, i.Position.Y)
        end
    end)
    uc = UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            mc:Disconnect(); uc:Disconnect()
            ghost:Destroy()
            local d = dragging; dragging = nil
            _finishDrag(d, i.Position)
        end
    end)
end

-- Wire drag + optional left-click on a button.
-- Drag starts only after DRAG_THRESHOLD px movement; clean release = click.
local function _wireDraggable(
    btn: TextButton,
    item: any,
    origin: string,
    slot: number?,
    onClickFn: (() -> ())?
)
    btn.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if dragging then return end
        local press   = Vector2.new(inp.Position.X, inp.Position.Y)
        local didDrag = false
        local mc: RBXScriptConnection
        local uc: RBXScriptConnection
        mc = UserInputService.InputChanged:Connect(function(mv)
            if mv.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            if not didDrag and (Vector2.new(mv.Position.X, mv.Position.Y) - press).Magnitude >= DRAG_THRESHOLD then
                didDrag = true
                mc:Disconnect(); uc:Disconnect()
                _launchGhost(btn, item, origin, slot, Vector2.new(mv.Position.X, mv.Position.Y))
            end
        end)
        uc = UserInputService.InputEnded:Connect(function(up)
            if up.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            mc:Disconnect(); uc:Disconnect()
            if not didDrag and onClickFn then onClickFn() end
        end)
    end)
end

-- ─── GUI bootstrap ────────────────────────────────────────────────────────────

local function _ensureGui(): ScreenGui
    if InventoryController._gui then return InventoryController._gui :: ScreenGui end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "InventoryUI"
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = false
    sg.Parent         = Players.LocalPlayer:WaitForChild("PlayerGui")

    -- ── Inventory panel ──────────────────────────────────────────────────────
    local root = Instance.new("Frame")
    root.Name             = "InventoryRoot"
    root.Size             = UDim2.new(0, 310, 0, 440)
    root.Position         = UDim2.new(1, -320, 0.08, 0)
    root.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    root.BorderSizePixel  = 0
    root.Parent           = sg
    _makeCorner(root, 10)
    -- subtle border
    _makeStroke(root, 1, Color3.fromRGB(55, 55, 80))

    -- Purple accent line at top
    local accent = Instance.new("Frame")
    accent.Size             = UDim2.new(1, -20, 0, 2)
    accent.Position         = UDim2.new(0, 10, 0, 0)
    accent.BackgroundColor3 = Color3.fromRGB(120, 100, 200)
    accent.BorderSizePixel  = 0
    accent.Parent           = root
    _makeCorner(accent, 2)

    -- Title
    local title = Instance.new("TextLabel")
    title.Size             = UDim2.new(1, -14, 0, 30)
    title.Position         = UDim2.new(0, 12, 0, 6)
    title.BackgroundTransparency = 1
    title.Text             = "INVENTORY"
    title.TextColor3       = Color3.fromRGB(200, 200, 220)
    title.Font             = Enum.Font.GothamBold
    title.TextSize         = 12
    title.TextXAlignment   = Enum.TextXAlignment.Left
    title.Parent           = root

    local closeHint = Instance.new("TextLabel")
    closeHint.Size             = UDim2.new(0, 70, 0, 16)
    closeHint.Position         = UDim2.new(1, -78, 0, 10)
    closeHint.BackgroundTransparency = 1
    closeHint.Text             = "[I] close"
    closeHint.TextColor3       = Color3.fromRGB(90, 90, 120)
    closeHint.Font             = Enum.Font.Gotham
    closeHint.TextSize         = 10
    closeHint.TextXAlignment   = Enum.TextXAlignment.Right
    closeHint.Parent           = root

    -- Divider
    local div = Instance.new("Frame")
    div.Size             = UDim2.new(1, -20, 0, 1)
    div.Position         = UDim2.new(0, 10, 0, 38)
    div.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    div.BorderSizePixel  = 0
    div.Parent           = root

    -- Stats bar
    local statsFrame = Instance.new("Frame")
    statsFrame.Name   = "StatsFrame"
    statsFrame.Size   = UDim2.new(1, 0, 0, 18)
    statsFrame.Position = UDim2.new(0, 0, 0, 42)
    statsFrame.BackgroundTransparency = 1
    statsFrame.Parent = root
    InventoryController._statsFrame = statsFrame

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name   = "StatsLabel"
    statsLabel.Size   = UDim2.new(1, -12, 1, 0)
    statsLabel.Position = UDim2.new(0, 12, 0, 0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text   = "0 items"
    statsLabel.TextColor3 = Color3.fromRGB(100, 100, 130)
    statsLabel.Font   = Enum.Font.Gotham
    statsLabel.TextSize = 10
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.Parent = statsFrame

    -- Search box
    local searchBox = Instance.new("TextBox")
    searchBox.Name  = "SearchBox"
    searchBox.Size  = UDim2.new(1, -16, 0, 24)
    searchBox.Position = UDim2.new(0, 8, 0, 62)
    searchBox.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    searchBox.BorderSizePixel  = 0
    searchBox.PlaceholderText  = "Search..."
    searchBox.Text             = ""
    searchBox.TextColor3       = Color3.fromRGB(200, 200, 220)
    searchBox.PlaceholderColor3 = Color3.fromRGB(70, 70, 95)
    searchBox.Font             = Enum.Font.Gotham
    searchBox.TextSize         = 11
    searchBox.ClearTextOnFocus = false
    searchBox.Parent           = root
    _makeCorner(searchBox, 5)
    _makeStroke(searchBox, 1, Color3.fromRGB(50, 50, 75))
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        InventoryController._search = string.lower(searchBox.Text)
        InventoryController:RefreshUI()
    end)

    -- Scroll
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name   = "Scroll"
    scroll.Size   = UDim2.new(1, -8, 1, -94)
    scroll.Position = UDim2.new(0, 4, 0, 90)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel        = 0
    scroll.ScrollBarThickness     = 3
    scroll.ScrollBarImageColor3   = Color3.fromRGB(70, 70, 100)
    scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
    scroll.Parent = root

    -- ── Hotbar ───────────────────────────────────────────────────────────────
    local hotbar = Instance.new("Frame")
    hotbar.Name             = "HotbarRoot"
    hotbar.AnchorPoint      = Vector2.new(0.5, 1)
    hotbar.Size             = UDim2.new(0, (SLOT_PX + SLOT_PAD) * HOTBAR_SIZE - SLOT_PAD + 16, 0, SLOT_PX + 20)
    hotbar.Position         = UDim2.new(0.5, 0, 1, -10)
    hotbar.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    hotbar.BorderSizePixel  = 0
    hotbar.Parent           = sg
    _makeCorner(hotbar, 8)
    _makeStroke(hotbar, 1, Color3.fromRGB(50, 50, 75))

    -- Hint (shown when panel is closed)
    local hint = Instance.new("TextLabel")
    hint.Name   = "Hint"
    hint.Size   = UDim2.new(0, 140, 0, 16)
    hint.Position = UDim2.new(0.5, -70, 0, 3)
    hint.BackgroundTransparency = 1
    hint.Text   = "[I] inventory"
    hint.TextColor3 = Color3.fromRGB(75, 75, 105)
    hint.Font   = Enum.Font.Gotham
    hint.TextSize = 10
    hint.Visible  = not InventoryController._isOpen
    hint.Parent   = sg

    InventoryController._gui = sg
    return sg
end

-- ─── RefreshUI ────────────────────────────────────────────────────────────────

function InventoryController:RefreshUI()
    local gui    = _ensureGui()
    local root   = gui:FindFirstChild("InventoryRoot") :: Frame?
    if not root then return end
    local scroll = root:FindFirstChild("Scroll") :: ScrollingFrame?
    if not scroll then return end

    -- Stats
    local inv          = self._aspectController and self._aspectController:GetInventory() or {}
    local equippedIds  = _equippedIdSet()
    local eqCount      = 0
    for _ in pairs(_getEquipped()) do eqCount += 1 end
    local sl = self._statsFrame and (self._statsFrame :: Frame):FindFirstChild("StatsLabel") :: TextLabel?
    if sl then sl.Text = string.format("%d items  •  %d slotted", #inv, eqCount) end

    -- Clear scroll
    for _, c in scroll:GetChildren() do
        if c:IsA("GuiObject") then c:Destroy() end
    end

    -- Filter: hide hotbarred items, apply search
    local filtered: {any} = {}
    for _, item in ipairs(inv) do
        if equippedIds[item.Id] then continue end
        if self._search ~= "" and not string.find(string.lower(item.Name or ""), self._search, 1, true) then continue end
        table.insert(filtered, item)
    end

    local cols  = 5
    local y     = 4
    local heldId = _heldWeaponRegistryId()

    -- ── Inventory grid ───────────────────────────────────────────────────────
    for _, cat in ipairs(CATEGORY_ORDER) do
        local catItems: {any} = {}
        for _, item in ipairs(filtered) do
            if item.Category == cat then table.insert(catItems, item) end
        end
        if #catItems == 0 then continue end

        -- Category header
        local hdrBg = CATEGORY_BG[cat] or Color3.fromRGB(40, 40, 55)
        local hdr = Instance.new("TextButton")
        hdr.Name  = "Hdr_" .. cat
        hdr.Size  = UDim2.new(1, -6, 0, 20)
        hdr.Position = UDim2.new(0, 3, 0, y)
        hdr.BackgroundColor3 = hdrBg
        hdr.BorderSizePixel  = 0
        hdr.Text  = (self._collapsed[cat] and "▶  " or "▼  ")
            .. (CATEGORY_DISPLAY[cat] or cat) .. "  (" .. #catItems .. ")"
        hdr.TextXAlignment = Enum.TextXAlignment.Left
        hdr.Font  = Enum.Font.GothamBold
        hdr.TextSize = 10
        hdr.TextColor3 = Color3.fromRGB(180, 180, 210)
        hdr.AutoButtonColor = false
        hdr.Parent = scroll
        _makeCorner(hdr, 4)
        hdr.MouseButton1Click:Connect(function()
            self._collapsed[cat] = not self._collapsed[cat]
            self:RefreshUI()
        end)
        -- Hover effect
        hdr.MouseEnter:Connect(function()
            hdr.BackgroundColor3 = Color3.fromRGB(
                math.min(hdrBg.R * 255 + 15, 255),
                math.min(hdrBg.G * 255 + 15, 255),
                math.min(hdrBg.B * 255 + 15, 255))
        end)
        hdr.MouseLeave:Connect(function() hdr.BackgroundColor3 = hdrBg end)
        y += 24

        if not self._collapsed[cat] then
            local col, row = 0, 0
            for _, item in ipairs(catItems) do
                local isAbility = (item.Category == "AspectMove")
                local tileBg    = CATEGORY_BG[cat] or Color3.fromRGB(40, 40, 55)
                local rarityCol = RARITY_STROKE[item.Rarity or "Common"] or Color3.fromRGB(110, 110, 110)

                local tile = Instance.new("TextButton")
                tile.Name  = "Inv_" .. item.Id
                tile.Size  = UDim2.new(0, SLOT_PX, 0, SLOT_PX)
                tile.Position = UDim2.new(0, 3 + col * (SLOT_PX + SLOT_PAD), 0, y + row * (SLOT_PX + SLOT_PAD))
                tile.BackgroundColor3 = tileBg
                tile.BorderSizePixel  = 0
                tile.Text  = ""
                tile.AutoButtonColor = false
                tile.Parent = scroll
                _makeCorner(tile, 5)
                _makeStroke(tile, 1.5, rarityCol)

                -- Item name strip (bottom)
                local nameStrip = Instance.new("Frame")
                nameStrip.Size  = UDim2.new(1, 0, 0, 15)
                nameStrip.Position = UDim2.new(0, 0, 1, -15)
                nameStrip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                nameStrip.BackgroundTransparency = 0.45
                nameStrip.BorderSizePixel = 0
                nameStrip.Parent = tile
                _makeCorner(nameStrip, 3)

                local nameLbl = Instance.new("TextLabel")
                nameLbl.Size  = UDim2.new(1, -4, 1, 0)
                nameLbl.Position = UDim2.new(0, 2, 0, 0)
                nameLbl.BackgroundTransparency = 1
                nameLbl.Text  = item.Name or item.Id
                nameLbl.TextColor3 = Color3.fromRGB(210, 210, 230)
                nameLbl.Font  = Enum.Font.Gotham
                nameLbl.TextSize = 9
                nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                nameLbl.Parent = nameStrip

                -- Ability drag-hint badge
                if isAbility then
                    local badge = Instance.new("TextLabel")
                    badge.Size  = UDim2.new(0, 24, 0, 12)
                    badge.Position = UDim2.new(0, 2, 0, 2)
                    badge.BackgroundColor3 = Color3.fromRGB(80, 55, 130)
                    badge.BackgroundTransparency = 0.25
                    badge.BorderSizePixel = 0
                    badge.Text  = "drag"
                    badge.TextColor3 = Color3.fromRGB(170, 150, 220)
                    badge.Font  = Enum.Font.Gotham
                    badge.TextSize = 8
                    badge.Parent = tile
                    _makeCorner(badge, 3)
                end

                -- Hover tint
                tile.MouseEnter:Connect(function()
                    tile.BackgroundColor3 = Color3.fromRGB(
                        math.min(tileBg.R * 255 + 12, 255),
                        math.min(tileBg.G * 255 + 12, 255),
                        math.min(tileBg.B * 255 + 12, 255))
                end)
                tile.MouseLeave:Connect(function() tile.BackgroundColor3 = tileBg end)

                if isAbility then
                    -- Abilities: drag only → click does nothing
                    _wireDraggable(tile, item, "inventory", nil, nil)
                else
                    -- Non-abilities: left-click → first empty hotbar slot; also draggable
                    _wireDraggable(tile, item, "inventory", nil, function()
                        for i = 1, HOTBAR_SIZE do
                            if not _getEquipped()[tostring(i)] then
                                _sendEquipItem(i, item.Id)
                                break
                            end
                        end
                    end)
                end

                col += 1
                if col >= cols then col = 0; row += 1 end
            end
            y += (row + 1) * (SLOT_PX + SLOT_PAD) + 6
        end
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, y + 8)

    -- ── Hotbar ────────────────────────────────────────────────────────────────

    local hotbar = gui:FindFirstChild("HotbarRoot") :: Frame?
    if not hotbar then return end

    for _, c in hotbar:GetChildren() do
        if c:IsA("GuiObject") and c.Name ~= "Accent" then c:Destroy() end
    end

    local slots: {[number]: any} = {}
    for k, v in pairs(_getEquipped()) do
        local n = tonumber(k); if n then slots[n] = v end
    end

    local renderEmpty = self._isOpen
    local toRender: {number} = {}
    for i = 1, HOTBAR_SIZE do
        if renderEmpty or slots[i] then table.insert(toRender, i) end
    end

    local vc     = #toRender
    local hbW    = vc * SLOT_PX + math.max(0, vc - 1) * SLOT_PAD + 16
    hotbar.Size  = UDim2.new(0, hbW, 0, SLOT_PX + 20)

    local rx = 8
    for _, idx in ipairs(toRender) do
        local item     = slots[idx]
        local regId    = item and (item.Category == "Weapons") and _toRegistryId(item.Id) or nil
        local isActive = regId ~= nil and regId == heldId
        local isAbility = item and item.Category == "AspectMove"
        local tileBg   = item and (CATEGORY_BG[item.Category] or Color3.fromRGB(40, 40, 55))
                         or Color3.fromRGB(22, 22, 32)

        local btn = Instance.new("TextButton")
        btn.Name  = "Slot_" .. idx
        btn.Size  = UDim2.new(0, SLOT_PX, 0, SLOT_PX)
        btn.Position = UDim2.new(0, rx, 0, 10)
        btn.BackgroundColor3 = tileBg
        btn.BorderSizePixel  = 0
        btn.Text  = ""
        btn.AutoButtonColor  = false
        btn.Parent = hotbar
        _makeCorner(btn, 5)

        -- Rarity / active outline (UIStroke)
        if isActive then
            -- Glowing white outline for held weapon
            local stroke = _makeStroke(btn, 2.5, ACTIVE_STROKE_COLOR)
            stroke.Enabled = true
            -- Subtle inner glow
            local glow = Instance.new("Frame")
            glow.Size  = UDim2.new(1, 0, 1, 0)
            glow.BackgroundColor3 = ACTIVE_BG_TINT
            glow.BackgroundTransparency = 0.88
            glow.BorderSizePixel = 0
            glow.ZIndex = btn.ZIndex
            glow.Parent = btn
            _makeCorner(glow, 5)
        elseif item then
            local rarityCol = RARITY_STROKE[item.Rarity or "Common"] or Color3.fromRGB(110, 110, 110)
            _makeStroke(btn, 1.5, rarityCol)
        else
            _makeStroke(btn, 1, Color3.fromRGB(38, 38, 58))
        end

        -- Slot number (top-left)
        local numLbl = Instance.new("TextLabel")
        numLbl.Size  = UDim2.new(0, 14, 0, 14)
        numLbl.Position = UDim2.new(0, 2, 0, 1)
        numLbl.BackgroundTransparency = 1
        numLbl.Text  = tostring(idx)
        numLbl.Font  = Enum.Font.GothamBold
        numLbl.TextSize = 9
        numLbl.TextColor3 = isActive
            and Color3.fromRGB(255, 248, 180)
            or (item and Color3.fromRGB(140, 140, 170) or Color3.fromRGB(55, 55, 80))
        numLbl.Parent = btn

        if item then
            -- Name strip (bottom)
            local nameStrip = Instance.new("Frame")
            nameStrip.Size  = UDim2.new(1, 0, 0, 15)
            nameStrip.Position = UDim2.new(0, 0, 1, -15)
            nameStrip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            nameStrip.BackgroundTransparency = 0.45
            nameStrip.BorderSizePixel = 0
            nameStrip.Parent = btn
            _makeCorner(nameStrip, 3)

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size  = UDim2.new(1, -4, 1, 0)
            nameLbl.Position = UDim2.new(0, 2, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text  = item.Name or item.Id
            nameLbl.TextColor3 = Color3.fromRGB(210, 210, 230)
            nameLbl.Font  = Enum.Font.Gotham
            nameLbl.TextSize = 9
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.Parent = nameStrip

            -- Hover tint
            btn.MouseEnter:Connect(function()
                btn.BackgroundColor3 = Color3.fromRGB(
                    math.min(tileBg.R * 255 + 14, 255),
                    math.min(tileBg.G * 255 + 14, 255),
                    math.min(tileBg.B * 255 + 14, 255))
            end)
            btn.MouseLeave:Connect(function() btn.BackgroundColor3 = tileBg end)

            local ci  = idx   -- captured slot index
            local cit = item  -- captured item

            _wireDraggable(btn, cit, "hotbar", ci, function()
                -- LEFT-CLICK on filled hotbar slot:
                if (cit :: any).Category == "AspectMove" then
                    -- Abilities: fire immediately, stay slotted
                    _useAbility((cit :: any).Id)
                elseif (cit :: any).Category == "Weapons" then
                    -- Weapons: toggle hold/unhold
                    local rid = _toRegistryId((cit :: any).Id)
                    if _heldWeaponRegistryId() == rid then
                        _unholdWeapon((cit :: any).Id)  -- already held → unhold
                    else
                        _holdWeapon((cit :: any).Id)    -- not held → hold
                    end
                    -- Note: left-click does NOT unequip weapons from hotbar.
                    -- To unequip a weapon, drag it back to inventory or use the
                    -- inventory panel while it's closed.
                else
                    -- Everything else: left-click unequips back to inventory
                    _sendUnequipItem(ci)
                end
            end)

        end -- end if item

        rx += SLOT_PX + SLOT_PAD
    end
end

-- ─── Inventory sync ───────────────────────────────────────────────────────────

local function _onInventoryUpdated()
    InventoryController:RefreshUI()
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function InventoryController:Init(dependencies: {[string]: any}?)
    print("[InventoryController] Initializing...")
    if dependencies then
        self._aspectController  = dependencies.AspectController
        self._networkController = dependencies.NetworkController
    end

    if self._aspectController and self._aspectController.OnInventoryChanged then
        self._aspectController:OnInventoryChanged(_onInventoryUpdated)
    end

    -- Toggle open/close
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local kc = input.KeyCode
        local isTick = kc == Enum.KeyCode.Backquote
            or (kc == Enum.KeyCode.Unknown
                and input.UserInputType == Enum.UserInputType.Keyboard
                and (input :: any).Character == "`")
        if isTick or kc == Enum.KeyCode.I then
            self:ToggleOpen()
        end
    end)

    -- Re-render hotbar when weapon hold state changes (active glow update)
    local function _watchChar(char: Model)
        char.ChildAdded:Connect(function(c)
            if c:IsA("Tool") then self:RefreshUI() end
        end)
        char.ChildRemoved:Connect(function(c)
            if c:IsA("Tool") then self:RefreshUI() end
        end)
    end
    local char = Players.LocalPlayer.Character
    if char then _watchChar(char) end
    Players.LocalPlayer.CharacterAdded:Connect(_watchChar)

    print("[InventoryController] Initialized")
end

function InventoryController:Start()
    print("[InventoryController] Started")
    self:RefreshUI()
end

function InventoryController:ToggleOpen()
    self._isOpen = not self._isOpen
    local gui  = _ensureGui()
    local root = gui:FindFirstChild("InventoryRoot") :: Frame?
    if root then
        local target = self._isOpen
            and UDim2.new(1, -320, 0.08, 0)
            or  UDim2.new(1,   10, 0.08, 0)
        TweenService:Create(root,
            TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Position = target }):Play()
    end
    local hint = gui:FindFirstChild("Hint") :: TextLabel?
    if hint then hint.Visible = not self._isOpen end
    self:RefreshUI()  -- rebuild hotbar compact/expanded
end

return InventoryController