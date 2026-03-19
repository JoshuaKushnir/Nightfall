--!strict
--[[
    Class: InventoryController
    Description: Client-side inventory panel, hotbar, drag-and-drop,
                 equip/unequip and hotbar number-key shortcuts.
    Dependencies: NetworkController, AspectController, WeaponRegistry

    Hotbar model:
        _equipped[slot] = item  →  item is SLOTTED in that hotbar position (persistent)
        Pressing a hotbar key / clicking a hotbar slot for a WEAPON toggles the
        in-hand state (EquipWeapon / UnequipWeapon) WITHOUT clearing the slot.
        Pressing for an ABILITY fires AbilityCastRequest.
        Items are only REMOVED from a slot by dragging off the hotbar.

    Bag model:
        Shows every item in _inventory that is NOT slotted in any hotbar slot.
        Clicking a bag item slots it (first free slot). Clicking an already-slotted
        item is impossible because slotted items are hidden from the bag.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local WeaponRegistry  = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local AnimationLoader = require(ReplicatedStorage.Shared.modules.AnimationLoader)
local localPlayer     = Players.LocalPlayer

-- ─── Layout ───────────────────────────────────────────────────────────────────

local HOTBAR_SLOTS = 8
local SLOT_OUTER   = 74    -- cell stride (px)
local SLOT_INNER   = 70    -- rendered slot size (px)
local INV_W        = 348
local INV_H        = 460

-- ─── Palette — dark soulslike / Deepwoken aesthetic ──────────────────────────
-- Aged iron, cracked stone, candlelit parchment. No softness — this is hardcore.

local PAL = {
    -- Panel chrome
    PANEL       = Color3.fromRGB(17, 14, 11),    -- almost-black warm charcoal
    PANEL_MID   = Color3.fromRGB(26, 21, 16),    -- card face — aged wood
    PANEL_RAISED= Color3.fromRGB(34, 28, 20),    -- slightly lighter surface
    HEADER_BG   = Color3.fromRGB(10,  8,  6),    -- near void for header
    DIVIDER     = Color3.fromRGB(72, 58, 40),    -- tarnished brass/gold line
    GOLD_LINE   = Color3.fromRGB(140, 108, 52),  -- bright accent gold line

    -- Slot chrome
    SLOT_BG     = Color3.fromRGB(20, 16, 12),    -- carved stone inset
    SLOT_HOVER  = Color3.fromRGB(36, 29, 20),    -- candlelight hover
    SLOT_HELD   = Color3.fromRGB(20, 16, 12),    -- held weapon — border tells story

    -- Text
    TEXT_PRI    = Color3.fromRGB(222, 208, 182), -- aged parchment
    TEXT_SEC    = Color3.fromRGB(138, 120,  96), -- faded ink
    TEXT_ACCENT = Color3.fromRGB(200, 164,  88), -- gold leaf
    TEXT_DIM    = Color3.fromRGB( 80,  68,  52), -- ghost text

    -- Search
    SEARCH_BG   = Color3.fromRGB(14, 11,  8),

    -- Scroll bar
    SCROLL_CLR  = Color3.fromRGB(110,  88,  56),
}

-- Category accent colours — desaturated war palette, no pastels
local CAT_COLOR: {[string]: Color3} = {
    Abilities    = Color3.fromRGB(100,  88, 180),  -- slate violet
    AspectMove   = Color3.fromRGB(100,  88, 180),
    Weapons      = Color3.fromRGB(168,  56,  48),  -- dried blood
    Tools        = Color3.fromRGB(158, 118,  44),  -- worn bronze
    Equipment    = Color3.fromRGB(120,  76, 140),  -- dark amethyst
    TrainingGear = Color3.fromRGB( 64, 128,  72),  -- forest iron
    Schematics   = Color3.fromRGB( 60, 140, 110),  -- verdigris
    QuestItems   = Color3.fromRGB(180, 148,  44),  -- antique gold
    Consumables  = Color3.fromRGB( 56, 140, 168),  -- cold water
    Relics       = Color3.fromRGB(178, 104,  30),  -- ember orange
    Materials    = Color3.fromRGB(108, 100,  88),  -- raw stone
}

-- Rarity — clear hierarchy, not garish
local RARITY_COLOR: {[string]: Color3} = {
    Common    = Color3.fromRGB(100,  96,  88),
    Uncommon  = Color3.fromRGB( 48, 160,  72),
    Rare      = Color3.fromRGB( 52, 100, 200),
    Legendary = Color3.fromRGB(210, 148,   0),
    Potion    = Color3.fromRGB(148,  40, 148),
    Elemental = Color3.fromRGB( 40, 175, 190),
}

local CAT_ORDER = {
    "Abilities","Weapons","Tools","Equipment",
    "TrainingGear","Schematics","QuestItems","Consumables","Relics","Materials",
}
local CAT_LABEL: {[string]: string} = {
    Abilities="Abilities", Weapons="Weapons",
    Tools="Tools", Equipment="Equipment", TrainingGear="Training Gear",
    Schematics="Schematics", QuestItems="Quest Items",
    Consumables="Consumables", Relics="Relics", Materials="Materials",
}

local HOTBAR_KEYS = {
    Enum.KeyCode.One, Enum.KeyCode.Two,   Enum.KeyCode.Three, Enum.KeyCode.Four,
    Enum.KeyCode.Five, Enum.KeyCode.Six,  Enum.KeyCode.Seven, Enum.KeyCode.Eight,
}

-- ─── Module ───────────────────────────────────────────────────────────────────

local InventoryController = {}
InventoryController._initialized      = false
InventoryController._isOpen           = false
InventoryController._aspectController  = nil :: any
InventoryController._networkController = nil :: any

-- _inventory  = full item list from server (all items, including slotted ones)
-- _equipped   = {["1"..="8"]: item}  hotbar slot assignments (persistent)
-- _heldSlot   = which slot is the currently held weapon (nil = sheathed)
InventoryController._inventory = {} :: {any}
InventoryController._equipped  = {} :: {[string]: any}
InventoryController._heldSlot  = nil :: number?

-- UI state
InventoryController._search    = ""
InventoryController._collapsed = {} :: {[string]: boolean}
for _, c in ipairs(CAT_ORDER) do InventoryController._collapsed[c] = false end

-- GUI refs
InventoryController._screenGui  = nil :: ScreenGui?
InventoryController._invRoot    = nil :: Frame?
InventoryController._hotbarRoot = nil :: Frame?

-- Tooltip state
InventoryController._tooltipRoot  = nil :: Frame?
InventoryController._tooltipItem  = nil :: any
InventoryController._hideDebounceId = 0

-- Drag
local _drag: {
    ghost:  Frame,
    item:   any,
    origin: string,
    slot:   number?,
    mc:     RBXScriptConnection,
    uc:     RBXScriptConnection,
} | nil = nil

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function _isAbility(item: any): boolean
    return item ~= nil and (item.Category == "Abilities" or item.Category == "AspectMove")
end
local function _isWeapon(item: any): boolean
    return item ~= nil and (item.Category == "Weapons" or item.Category == "Weapon")
end
local function _isTrainingTool(item: any): boolean
    return item ~= nil and item.Category == "Tools" and item.TrainingToolId ~= nil
end

-- Check if a training tool is equipable (can be held like a weapon)
local function _isEquippableTrainingTool(item: any): boolean
    return _isTrainingTool(item) and item.IsEquipable == true
end

-- Get weapon registry ID for a training tool (uses its ID as weapon ID)
local function _trainingToolRegId(item: any): string
    return item.Id
end

local function _slotOf(self: any, itemId: string): number?
    for i = 1, HOTBAR_SLOTS do
        local e = self._equipped[tostring(i)]
        if e and e.Id == itemId then return i end
    end
    return nil
end
local function _freeSlot(self: any): number?
    for i = 1, HOTBAR_SLOTS do
        if not self._equipped[tostring(i)] then return i end
    end
    return nil
end
local function _nonAbilitySlot(self: any): number?
    for i = 1, HOTBAR_SLOTS do
        local e = self._equipped[tostring(i)]
        if e and not _isAbility(e) then return i end
    end
    return nil
end

local function _weaponRegId(item: any): string
    if type(item.WeaponId) == "string" and item.WeaponId ~= "" then return item.WeaponId end
    local id: string = tostring(item.Id or "")
    return id:match("^weapon_(.+)$") or id
end

-- ─── Anim stub ────────────────────────────────────────────────────────────────

local function _playUnequipAnim(regId: string)
    local char = localPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not hum then return end
    local cfg = WeaponRegistry.Get(regId)
    local entry = cfg and cfg.Animations and (cfg.Animations :: any).Unequip
    if not entry then
        -- VFX STUB: unequip animation for regId — deferred, not a programmer task
        return
    end
    task.spawn(function()
        local track = AnimationLoader.LoadTrack(hum, entry.Folder, entry.Asset)
        if track then track:Play(); track.Stopped:Wait(); track:Destroy() end
    end)
end

-- ─── Network ──────────────────────────────────────────────────────────────────

-- Slot an item into a hotbar slot (tells server to record assignment).
-- Does NOT equip the weapon tool into hand — that's _doHold.
local function _slotItem(self: any, slot: number, item: any)
    self._equipped[tostring(slot)] = item
    if self._networkController then
        self._networkController:SendToServer("EquipItem", {Slot = tostring(slot), ItemId = item.Id})
    end
end

-- Remove an item from a hotbar slot (tells server).
-- For weapons, also unequips the tool if it was being held.
local function _unslotItem(self: any, slot: number)
    local item = self._equipped[tostring(slot)]
    self._equipped[tostring(slot)] = nil
    if self._networkController then
        self._networkController:SendToServer("UnequipItem", {Slot = tostring(slot)})
    end
    if item and (_isWeapon(item) or _isEquippableTrainingTool(item)) then
        if self._heldSlot == slot then
            self._heldSlot = nil
            _playUnequipAnim(_weaponRegId(item))
            local remote = NetworkProvider:GetRemoteEvent("UnequipWeapon")
            if remote then remote:FireServer() end
        end
    end
end

-- Toggle weapon hold state without touching the slot assignment.
local function _toggleHold(self: any, slot: number)
    local item = self._equipped[tostring(slot)]
    if not item then return end
    if not _isWeapon(item) and not _isEquippableTrainingTool(item) then return end

    if self._heldSlot == slot then
        -- Currently held → sheathe (unequip tool, keep slot)
        self._heldSlot = nil
        local regId = _isWeapon(item) and _weaponRegId(item) or _trainingToolRegId(item)
        _playUnequipAnim(regId)
        local remote = NetworkProvider:GetRemoteEvent("UnequipWeapon")
        if remote then remote:FireServer() end
    else
        -- Not held → draw (equip tool)
        -- If another slot was held, sheathe it first
        if self._heldSlot then
            local prevItem = self._equipped[tostring(self._heldSlot)]
            if prevItem and (_isWeapon(prevItem) or _isEquippableTrainingTool(prevItem)) then
                local prevRegId = _isWeapon(prevItem) and _weaponRegId(prevItem) or _trainingToolRegId(prevItem)
                _playUnequipAnim(prevRegId)
                local remote = NetworkProvider:GetRemoteEvent("UnequipWeapon")
                if remote then remote:FireServer() end
            end
        end
        self._heldSlot = slot
        local remote = NetworkProvider:GetRemoteEvent("EquipWeapon")
        local regId = _isWeapon(item) and _weaponRegId(item) or _trainingToolRegId(item)
        if remote then remote:FireServer(regId) end
    end
end

-- ─── Click handlers ───────────────────────────────────────────────────────────

local function _onHotbarActivate(self: any, slot: number)
    local item = self._equipped[tostring(slot)]
    if not item then return end
    if _isAbility(item) then
        -- route through ActionController so ability integrates with combo pipeline
        local abilityId = item.AbilityId or item.Id
        local mouse = localPlayer:GetMouse()
        local ac = self._actionController
        if ac and ac.PlayAbilityAction then
            ac.PlayAbilityAction(abilityId, mouse.Hit.p)
        else
            NetworkProvider:FireServer("AbilityCastRequest", {AbilityId = abilityId, TargetPosition = mouse.Hit.p})
        end
    elseif _isWeapon(item) or _isEquippableTrainingTool(item) then
        _toggleHold(self, slot)
        self:RefreshUI()
    elseif _isTrainingTool(item) then
        -- Non-equippable training tool - use directly (legacy behavior)
        if self._networkController then
            self._networkController:SendToServer("UseTrainingTool", {Slot = tostring(slot), ItemId = item.Id})
        end
    else
        if self._networkController then
            self._networkController:SendToServer("UseItem", {Slot = tostring(slot), ItemId = item.Id})
        end
    end
end

local function _onBagClick(self: any, item: any)
    -- Bag only shows un-slotted items, so this is always a fresh slot operation
    if _isAbility(item) then
        local hasAny = false
        for i = 1, HOTBAR_SLOTS do if self._equipped[tostring(i)] then hasAny = true; break end end
        if hasAny then
                    -- Cast immediately if hotbar already occupied
            local abilityId = item.AbilityId or item.Id
            local mouse = localPlayer:GetMouse()
            local ac = self._actionController
            if ac and ac.PlayAbilityAction then
                ac.PlayAbilityAction(abilityId, mouse.Hit.p)
            else
                NetworkProvider:FireServer("AbilityCastRequest", {AbilityId = abilityId, TargetPosition = mouse.Hit.p})
            end
            return
        end
        local slot = _freeSlot(self) or 1
        _slotItem(self, slot, item)
    else
        -- Non-ability: one at a time; replace any existing non-ability slot
        local prev = _nonAbilitySlot(self)
        if prev then _unslotItem(self, prev) end
        local slot = _freeSlot(self) or 1
        _slotItem(self, slot, item)
        -- Auto-draw the weapon
        if _isWeapon(item) then
            self._heldSlot = slot
            local remote = NetworkProvider:GetRemoteEvent("EquipWeapon")
            if remote then remote:FireServer(_weaponRegId(item)) end
        end
    end
    self:RefreshUI()
end

-- ─── Drag ─────────────────────────────────────────────────────────────────────

local function _endDrag(self: any, mousePos: Vector3)
    if not _drag then return end
    local drag = _drag
    local hotbar = self._hotbarRoot :: Frame?
    if hotbar then
        local abs = hotbar.AbsolutePosition
        local sz  = hotbar.AbsoluteSize
        local lx  = mousePos.X - abs.X
        local ly  = mousePos.Y - abs.Y
        if lx >= 0 and ly >= 0 and lx <= sz.X and ly <= sz.Y then
            local tgt = math.clamp(math.floor(lx / SLOT_OUTER) + 1, 1, HOTBAR_SLOTS)
            if drag.origin == "bag" then
                if self._equipped[tostring(tgt)] then _unslotItem(self, tgt) end
                _slotItem(self, tgt, drag.item)
            elseif drag.origin == "hotbar" and drag.slot and drag.slot ~= tgt then
                local ia = self._equipped[tostring(drag.slot)]
                local ib = self._equipped[tostring(tgt)]
                self._equipped[tostring(drag.slot)] = ib
                self._equipped[tostring(tgt)]       = ia
                if ia then _slotItem(self, tgt, ia) else _unslotItem(self, tgt) end
                if ib then _slotItem(self, drag.slot, ib) else _unslotItem(self, drag.slot) end
                -- Update _heldSlot if swapped
                if self._heldSlot == drag.slot then self._heldSlot = tgt
                elseif self._heldSlot == tgt then self._heldSlot = drag.slot end
            end
        else
            -- Dropped off hotbar → remove slot assignment only
            if drag.origin == "hotbar" and drag.slot then
                _unslotItem(self, drag.slot)
            end
        end
    end
    self:RefreshUI()
end

local function _startDrag(self: any, item: any, origin: string, slot: number?)
    if _drag then return end
    local ghost = Instance.new("Frame")
    ghost.Name               = "DragGhost"
    ghost.Size               = UDim2.fromOffset(SLOT_INNER, SLOT_INNER)
    ghost.AnchorPoint        = Vector2.new(0.5, 0.5)
    ghost.BackgroundColor3   = CAT_COLOR[item.Category or "Materials"] or PAL.SLOT_HELD
    ghost.BackgroundTransparency = 0.3
    ghost.BorderSizePixel    = 0
    ghost.ZIndex             = 1000
    local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0,5); gc.Parent = ghost
    local gl = Instance.new("TextLabel")
    gl.Size = UDim2.fromScale(1,1); gl.BackgroundTransparency = 1
    gl.TextColor3 = PAL.TEXT_PRI; gl.TextScaled = true
    gl.Text = item.Name or "?"; gl.Font = Enum.Font.Antique
    gl.ZIndex = 1001; gl.Parent = ghost
    ghost.Parent = self._screenGui

    local mc: RBXScriptConnection
    local uc: RBXScriptConnection
    mc = UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then
            ghost.Position = UDim2.fromOffset(inp.Position.X, inp.Position.Y)
        end
    end)
    uc = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            mc:Disconnect(); uc:Disconnect(); ghost:Destroy()
            if _drag then _endDrag(self, inp.Position); _drag = nil end
        end
    end)
    _drag = { ghost=ghost, item=item, origin=origin, slot=slot, mc=mc, uc=uc }
end

-- ─── Tooltip helpers ──────────────────────────────────────────────────────────

local function _initTooltip(self: any)
    if self._tooltipRoot then return end
    local gui = self._screenGui
    if not gui then return end
    self._tooltipRoot = gui:WaitForChild("TooltipRoot") :: Frame?
    if self._tooltipRoot then
        self._tooltipRoot.Visible = false
    end
end

local function _positionTooltip(self: any)
    if not self._tooltipRoot then return end
    local mouse = localPlayer:GetMouse()
    local offset = Vector2.new(18, 20)
    local x = mouse.X + offset.X
    local y = mouse.Y + offset.Y

    -- Clamp so tooltip stays on screen
    local gui = self._screenGui
    if gui then
        local viewX, viewY = workspace.CurrentCamera.ViewportSize.X, workspace.CurrentCamera.ViewportSize.Y
        local size = self._tooltipRoot.AbsoluteSize
        if x + size.X > viewX - 10 then
            x = viewX - size.X - 10
        end
        if y + size.Y > viewY - 10 then
            y = viewY - size.Y - 10
        end
    end

    self._tooltipRoot.Position = UDim2.fromOffset(x, y)
end

local function _fillTooltip(self: any, item: any)
    if not self._tooltipRoot then return end
    self._tooltipItem = item

    local title    = self._tooltipRoot:FindFirstChild("Title") :: TextLabel?
    local subtitle = self._tooltipRoot:FindFirstChild("Subtitle") :: TextLabel?
    local body     = self._tooltipRoot:FindFirstChild("Body") :: TextLabel?
    local tagsRoot = self._tooltipRoot:FindFirstChild("TagContainer") :: Frame?

    if title then
        title.Text = item.Name or "Unknown"
    end

    local cat  = item.Category or "Materials"
    local rare = item.Rarity or "Common"
    if subtitle then
        subtitle.Text = string.format("%s • %s", cat, rare)
        subtitle.TextColor3 = RARITY_COLOR[rare] or PAL.TEXT_ACCENT
    end

    if body then
        body.Text = item.Description or ""
    end

    if tagsRoot then
        for _, child in ipairs(tagsRoot:GetChildren()) do
            if child:IsA("TextLabel") and child.Name ~= "UIListLayout" then
                child:Destroy()
            end
        end
        if item.Tags and #item.Tags > 0 then
            for _, tag in ipairs(item.Tags) do
                local l = Instance.new("TextLabel")
                l.BackgroundTransparency = 1
                l.Size = UDim2.new(0, 0, 0, 18)
                l.AutomaticSize = Enum.AutomaticSize.X
                l.Font = Enum.Font.Gotham
                l.TextSize = 12
                l.Text = tag
                l.TextColor3 = PAL.TEXT_DIM
                l.Parent = tagsRoot
            end
        end
    end
end

local function _showTooltip(self: any, item: any)
    _initTooltip(self)
    if not self._tooltipRoot then return end
    _fillTooltip(self, item)
    _positionTooltip(self)
    self._tooltipRoot.Visible = true
end

local function _hideTooltip(self: any, item: any?)
    self._hideDebounceId += 1
    local thisId = self._hideDebounceId
    task.delay(0.05, function()
        if thisId ~= self._hideDebounceId then return end
        if not self._tooltipRoot then return end
        if item and self._tooltipItem and item.Id ~= self._tooltipItem.Id then
            return
        end
        self._tooltipItem = nil
        self._tooltipRoot.Visible = false
    end)
end

local function _bindSlotHover(self: any, button: TextButton, item: any)
    button.MouseEnter:Connect(function()
        _showTooltip(self, item)
    end)
    button.MouseLeave:Connect(function()
        _hideTooltip(self, item)
    end)
    if button.SelectionGained then
        button.SelectionGained:Connect(function()
            _showTooltip(self, item)
        end)
    end
    if button.SelectionLost then
        button.SelectionLost:Connect(function()
            _hideTooltip(self, item)
        end)
    end
end

-- ─── GUI helpers ──────────────────────────────────────────────────────────────

local function _corner(parent: Instance, r: number)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = parent
end

local function _stroke(parent: Instance, color: Color3, thick: number, trans: number?)
    local s = Instance.new("UIStroke")
    s.Color       = color
    s.Thickness   = thick
    s.Transparency = trans or 0
    s.Parent      = parent
end

-- Horizontal rule / divider line
local function _divider(parent: Instance, yPos: number, width: number?)
    local d = Instance.new("Frame")
    d.Size             = UDim2.new(if width then 0 else 1, width or 0, 0, 1)
    d.Position         = UDim2.fromOffset(0, yPos)
    d.BackgroundColor3 = PAL.DIVIDER
    d.BorderSizePixel  = 0
    d.Parent           = parent
end

-- ─── UI Layout Helpers ──────────────────────────────────────────────────────────

local function _styleSlot(frame: Frame, selected: boolean?)
    frame.BackgroundColor3 = selected and PAL.SLOT_HOVER or PAL.SLOT_BG
    frame.BorderColor3 = PAL.DIVIDER
    frame.BorderSizePixel = selected and 2 or 1
end

local function _createInventoryRoot(self: any)
    local gui = self._screenGui
    local root = Instance.new("Frame")
    root.Name = "InventoryRoot"
    root.Size = UDim2.new(0.38, 0, 0.6, 0)    -- left panel: 38% width, 60% height
    -- Start OFF-SCREEN (panel starts closed)
    root.Position = UDim2.new(-0.4, 0, 0.07, 0)
    root.BackgroundColor3 = PAL.PANEL
    root.BackgroundTransparency = 0.15
    root.BorderColor3 = PAL.GOLD_LINE
    root.BorderSizePixel = 1
    root.Parent = gui
    _corner(root, 3)

    local padding = Instance.new("UIPadding")
    padding.PaddingTop    = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft   = UDim.new(0, 12)
    padding.PaddingRight  = UDim.new(0, 12)
    padding.Parent = root

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder     = Enum.SortOrder.LayoutOrder
    layout.Padding       = UDim.new(0, 8)
    layout.Parent = root

    self._invRoot = root
end

local function _createBagSection(self: any)
    local bagFrame = Instance.new("Frame")
    bagFrame.Name = "BagSection"
    bagFrame.Size = UDim2.new(1, 0, 1, 0)   -- fill entire inventory root vertically
    bagFrame.BackgroundColor3 = PAL.PANEL_MID
    bagFrame.BackgroundTransparency = 0.05
    bagFrame.BorderColor3 = PAL.DIVIDER
    bagFrame.BorderSizePixel = 1
    bagFrame.LayoutOrder = 1
    bagFrame.Parent = self._invRoot
    _corner(bagFrame, 2)

    local padding = Instance.new("UIPadding")
    padding.PaddingTop    = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft   = UDim.new(0, 8)
    padding.PaddingRight  = UDim.new(0, 8)
    padding.Parent = bagFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder     = Enum.SortOrder.LayoutOrder
    layout.Padding       = UDim.new(0, 6)
    layout.Parent = bagFrame

    -- Header row (title + search)
    local header = Instance.new("Frame")
    header.Name = "HeaderRow"
    header.Size = UDim2.new(1, 0, 0, 32)
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = bagFrame

    local headerLayout = Instance.new("UIListLayout")
    headerLayout.FillDirection = Enum.FillDirection.Horizontal
    headerLayout.SortOrder     = Enum.SortOrder.LayoutOrder
    headerLayout.Padding       = UDim.new(0, 8)
    headerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    headerLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
    headerLayout.Parent = header

    local title = Instance.new("TextLabel")
    title.Name = "BagTitle"
    title.Size = UDim2.new(0, 120, 1, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = PAL.TEXT_PRI
    title.Text = "INVENTORY"
    title.Parent = header

    local searchBox = Instance.new("TextBox")
    searchBox.Name = "SearchBox"
    searchBox.Size = UDim2.new(1, -128, 1, 0)
    searchBox.BackgroundColor3 = PAL.SEARCH_BG
    searchBox.BackgroundTransparency = 0
    searchBox.BorderColor3 = PAL.DIVIDER
    searchBox.BorderSizePixel = 1
    searchBox.ClearTextOnFocus = false
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 12
    searchBox.TextColor3 = PAL.TEXT_PRI
    searchBox.PlaceholderText = "Search..."
    searchBox.PlaceholderColor3 = PAL.TEXT_DIM
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.Parent = header
    _corner(searchBox, 1)

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self._search = string.lower(searchBox.Text)
        self:RefreshUI()
    end)

    -- Scrollable area with vertical layout for category blocks
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "BagScroll"
    scroll.Size = UDim2.new(1, 0, 1, -54)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollBarThickness = 2
    scroll.ScrollBarImageColor3 = PAL.SCROLL_CLR
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.LayoutOrder = 2
    scroll.Parent = bagFrame

    local scrollLayout = Instance.new("UIListLayout")
    scrollLayout.FillDirection = Enum.FillDirection.Vertical
    scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scrollLayout.Padding = UDim.new(0, 6)
    scrollLayout.Parent = scroll

    self._bagScroll = scroll
end



local function _createHotbar(self: any)
    local gui = self._screenGui
    local hb = Instance.new("Frame")
    hb.Name = "HotbarRoot"
    hb.AnchorPoint = Vector2.new(0.5, 1)
    hb.Position = UDim2.new(0.5, 0, 1, -18)    -- bottom center
    hb.Size = UDim2.new(0, HOTBAR_SLOTS * SLOT_OUTER + 16, 0, SLOT_INNER + 26)
    hb.BackgroundTransparency = 1
    hb.BorderSizePixel = 0
    hb.Parent = gui

    local slotsFrame = Instance.new("Frame")
    slotsFrame.Name = "Slots"
    slotsFrame.Size = UDim2.new(1, 0, 1, 0)
    slotsFrame.BackgroundTransparency = 1
    slotsFrame.Parent = hb

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment   = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 8)
    layout.Parent = slotsFrame

    self._hotbarRoot = hb
end

-- ─── Build GUI (once) ─────────────────────────────────────────────────────────

local function _buildGui(self: any)
    local sg = Instance.new("ScreenGui")
    sg.Name           = "InventoryUI"
    sg.ResetOnSpawn   = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset = false
    sg.Parent         = localPlayer:WaitForChild("PlayerGui")

    self._screenGui = sg

    _createInventoryRoot(self)
    _createBagSection(self)
    _createHotbar(self)

    -- ── Tooltip frame ────────────────────────────────────────────────────────
    local tooltip = Instance.new("Frame")
    tooltip.Name             = "TooltipRoot"
    tooltip.BackgroundColor3 = PAL.PANEL_RAISED
    tooltip.BackgroundTransparency = 0
    tooltip.BorderSizePixel  = 1
    tooltip.BorderColor3     = PAL.GOLD_LINE
    tooltip.Visible          = false
    tooltip.AutomaticSize    = Enum.AutomaticSize.XY
    tooltip.AnchorPoint      = Vector2.new(0, 0)
    tooltip.ZIndex           = 100
    tooltip.Parent           = sg
    _corner(tooltip, 3)

    -- Padding inside tooltip
    local tooltip_padding = Instance.new("UIPadding")
    tooltip_padding.PaddingLeft   = UDim.new(0, 8)
    tooltip_padding.PaddingRight  = UDim.new(0, 8)
    tooltip_padding.PaddingTop    = UDim.new(0, 8)
    tooltip_padding.PaddingBottom = UDim.new(0, 8)
    tooltip_padding.Parent        = tooltip

    -- Vertical list layout for title / subtitle / body / tags
    local tooltip_layout = Instance.new("UIListLayout")
    tooltip_layout.FillDirection = Enum.FillDirection.Vertical
    tooltip_layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    tooltip_layout.VerticalAlignment   = Enum.VerticalAlignment.Top
    tooltip_layout.Padding = UDim.new(0, 4)
    tooltip_layout.Parent  = tooltip

    -- Title
    local tooltip_title = Instance.new("TextLabel")
    tooltip_title.Name               = "Title"
    tooltip_title.Size               = UDim2.new(0, 0, 0, 0)
    tooltip_title.AutomaticSize      = Enum.AutomaticSize.XY
    tooltip_title.BackgroundTransparency = 1
    tooltip_title.TextColor3         = PAL.TEXT_PRI
    tooltip_title.Font               = Enum.Font.Antique
    tooltip_title.TextSize           = 14
    tooltip_title.TextWrapped        = true
    tooltip_title.TextXAlignment     = Enum.TextXAlignment.Left
    tooltip_title.Text               = "Item Name"
    tooltip_title.Parent             = tooltip

    -- Subtitle (Category • Rarity)
    local tooltip_subtitle = Instance.new("TextLabel")
    tooltip_subtitle.Name               = "Subtitle"
    tooltip_subtitle.Size               = UDim2.new(0, 0, 0, 0)
    tooltip_subtitle.AutomaticSize      = Enum.AutomaticSize.XY
    tooltip_subtitle.BackgroundTransparency = 1
    tooltip_subtitle.TextColor3         = PAL.TEXT_ACCENT
    tooltip_subtitle.Font               = Enum.Font.Gotham
    tooltip_subtitle.TextSize           = 11
    tooltip_subtitle.Text               = ""
    tooltip_subtitle.Parent             = tooltip

    -- Body (Description)
    local tooltip_body = Instance.new("TextLabel")
    tooltip_body.Name               = "Body"
    tooltip_body.Size               = UDim2.new(0, 240, 0, 0)
    tooltip_body.AutomaticSize      = Enum.AutomaticSize.Y
    tooltip_body.BackgroundTransparency = 1
    tooltip_body.TextColor3         = PAL.TEXT_SEC
    tooltip_body.Font               = Enum.Font.Gotham
    tooltip_body.TextSize           = 11
    tooltip_body.TextWrapped        = true
    tooltip_body.TextXAlignment     = Enum.TextXAlignment.Left
    tooltip_body.TextYAlignment     = Enum.TextYAlignment.Top
    tooltip_body.Text               = ""
    tooltip_body.Parent             = tooltip

    -- Tag container
    local tag_container = Instance.new("Frame")
    tag_container.Name               = "TagContainer"
    tag_container.Size               = UDim2.new(0, 240, 0, 0)
    tag_container.AutomaticSize      = Enum.AutomaticSize.Y
    tag_container.BackgroundTransparency = 1
    tag_container.Parent             = tooltip

    local tag_layout = Instance.new("UIListLayout")
    tag_layout.FillDirection = Enum.FillDirection.Horizontal
    tag_layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    tag_layout.VerticalAlignment   = Enum.VerticalAlignment.Top
    tag_layout.Padding = UDim.new(0, 4)
    tag_layout.Parent  = tag_container
end

-- ─── RefreshUI ────────────────────────────────────────────────────────────────

function InventoryController:RefreshUI()
    if not self._screenGui then return end
    local invRoot = self._invRoot     :: Frame
    local scroll  = self._bagScroll   :: ScrollingFrame
    local hotbar  = self._hotbarRoot  :: Frame

    -- Build set of slotted item IDs → don't show in bag
    local slottedIds: {[string]: boolean} = {}
    local hasAny = false
    for i = 1, HOTBAR_SLOTS do
        local item = self._equipped[tostring(i)]
        if item then slottedIds[item.Id] = true; hasAny = true end
    end

    -- ── BAG ───────────────────────────────────────────────────────────────────
    -- Clear old category blocks
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
    end

    local search = string.lower(self._search)

    -- Group items by category
    local groups: {[string]: {any}} = {}
    for _, item in ipairs(self._inventory) do
        if slottedIds[item.Id] then continue end
        if search ~= "" and not string.find(string.lower(item.Name or ""), search, 1, true) then continue end
        local cat = item.Category or "Materials"
        if cat == "AspectMove" then cat = "Abilities" end
        if not groups[cat] then groups[cat] = {} end
        table.insert(groups[cat], item)
    end

    -- Create category blocks with internal grids
    for _, cat in ipairs(CAT_ORDER) do
        local items = groups[cat]
        if not items or #items == 0 then continue end

        local catColor = CAT_COLOR[cat] or PAL.TEXT_SEC

        -- Category block — wraps header + grid
        local block = Instance.new("Frame")
        block.Name = "Cat_" .. cat
        block.BackgroundTransparency = 1
        block.Size = UDim2.new(1, -16, 0, 0)
        block.AutomaticSize = Enum.AutomaticSize.Y
        block.Parent = scroll

        local blockLayout = Instance.new("UIListLayout")
        blockLayout.FillDirection = Enum.FillDirection.Vertical
        blockLayout.SortOrder = Enum.SortOrder.LayoutOrder
        blockLayout.Padding = UDim.new(0, 4)
        blockLayout.Parent = block

        -- Category header with collapse toggle
        local catHdr = Instance.new("TextButton")
        catHdr.Name = "Header"
        catHdr.Size = UDim2.new(1, 0, 0, 20)
        catHdr.BackgroundTransparency = 1
        catHdr.AutoButtonColor = false
        catHdr.Text = (self._collapsed[cat] and "▸  " or "▾  ") .. string.upper(CAT_LABEL[cat] or cat)
        catHdr.TextColor3 = PAL.TEXT_ACCENT
        catHdr.Font = Enum.Font.Antique
        catHdr.TextSize = 12
        catHdr.TextXAlignment = Enum.TextXAlignment.Left
        catHdr.Parent = block

        local rule = Instance.new("Frame")
        rule.Size = UDim2.new(1, 0, 0, 1)
        rule.BackgroundColor3 = PAL.DIVIDER
        rule.BorderSizePixel = 0
        rule.Parent = block

        local capturedCat = cat
        catHdr.MouseButton1Click:Connect(function()
            self._collapsed[capturedCat] = not self._collapsed[capturedCat]
            self:RefreshUI()
        end)

        if self._collapsed[cat] then continue end

        -- Grid frame for items
        local grid = Instance.new("Frame")
        grid.Name = "Grid"
        grid.BackgroundTransparency = 1
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.Parent = block

        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0, 70, 0, 70)
        gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
        gridLayout.FillDirectionMaxCells = 4
        gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        gridLayout.Parent = grid

        -- Build cards for items in this category
        for _, item in ipairs(items) do
            local rarity = item.Rarity or "Common"
            local rarityCol = RARITY_COLOR[rarity] or PAL.TEXT_SEC

            local card = Instance.new("Frame")
            card.Name = "Card_" .. item.Id
            card.BackgroundColor3 = PAL.PANEL_MID
            card.BorderSizePixel = 0
            card.Parent = grid
            _corner(card, 2)
            _stroke(card, rarityCol, 1, 0.25)

            -- Category stripe
            local stripe = Instance.new("Frame")
            stripe.Size = UDim2.new(0, 3, 1, 0)
            stripe.BackgroundColor3 = catColor
            stripe.BackgroundTransparency = 0.1
            stripe.BorderSizePixel = 0
            stripe.Parent = card
            _corner(stripe, 1)

            -- Item name label
            local nameL = Instance.new("TextLabel")
            nameL.Size = UDim2.new(1, -8, 1, -8)
            nameL.Position = UDim2.fromOffset(7, 4)
            nameL.BackgroundTransparency = 1
            nameL.TextColor3 = PAL.TEXT_PRI
            nameL.TextWrapped = true
            nameL.TextScaled = true
            nameL.Font = Enum.Font.Antique
            nameL.Text = item.Name or "?"
            nameL.Parent = card

            -- Click/drag button
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromScale(1, 1)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.AutoButtonColor = false
            btn.Parent = card

            local ci = item

            btn.MouseEnter:Connect(function()
                card.BackgroundColor3 = PAL.SLOT_HOVER
                _showTooltip(self, ci)
            end)

            btn.MouseLeave:Connect(function()
                card.BackgroundColor3 = PAL.PANEL_MID
                _hideTooltip(self, ci)
            end)

            btn.MouseButton1Click:Connect(function() _onBagClick(self, ci) end)
            btn.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    _startDrag(self, ci, "bag", nil)
                end
            end)
        end
    end

    -- ── HOTBAR ────────────────────────────────────────────────────────────────
    for _, c in ipairs(hotbar:GetChildren()) do c:Destroy() end

    local function _buildHotbarSlot(xi: number, slotIdx: number, item: any?)
        local x      = xi * SLOT_OUTER
        local isHeld = item ~= nil and _isWeapon(item) and self._heldSlot == slotIdx
        local catCol = item and (CAT_COLOR[item.Category] or PAL.TEXT_SEC) or nil

        -- Slot background — carved stone inset feel
        local bg = Instance.new("Frame")
        bg.Name             = "HBg"..slotIdx
        bg.Size             = UDim2.fromOffset(SLOT_INNER, SLOT_INNER)
        bg.Position         = UDim2.fromOffset(x, 0)
        bg.BackgroundColor3 = PAL.SLOT_BG
        bg.BorderSizePixel  = 0
        bg.Parent           = hotbar
        _corner(bg, 2)

        if item then
            -- Slotted item: category-coloured border, brighter when held
            local borderAlpha = isHeld and 0 or 0.55
            local borderThick = isHeld and 2 or 1
            _stroke(bg, catCol :: Color3, borderThick, borderAlpha)

            -- Top stripe — same category colour
            local stripe = Instance.new("Frame")
            stripe.Size = UDim2.new(1, 0, 0, 2)
            stripe.BackgroundColor3 = catCol :: Color3
            stripe.BackgroundTransparency = isHeld and 0 or 0.6
            stripe.BorderSizePixel = 0
            stripe.Parent = bg

            -- Cooldown Overlay — scales top to bottom based on remaining time
            if _isAbility(item) then
                local cdOverlay = Instance.new("Frame")
                cdOverlay.Name               = "CooldownOverlay"
                cdOverlay.Size               = UDim2.fromScale(1, 1) -- default full
                cdOverlay.Position           = UDim2.fromScale(0, 0)
                cdOverlay.BackgroundColor3   = Color3.new(0,0,0)
                cdOverlay.BackgroundTransparency = 0.6
                cdOverlay.BorderSizePixel    = 0
                cdOverlay.ZIndex             = bg.ZIndex + 2
                cdOverlay.Visible            = false
                cdOverlay.Parent             = bg

                local cdLabel = Instance.new("TextLabel")
                cdLabel.Name               = "CooldownLabel"
                cdLabel.Size               = UDim2.fromScale(1, 1)
                cdLabel.BackgroundTransparency = 1
                cdLabel.TextColor3         = Color3.new(1, 1, 1)
                cdLabel.TextSize           = 14
                cdLabel.Font               = Enum.Font.Antique
                cdLabel.ZIndex             = cdOverlay.ZIndex + 1
                cdLabel.Visible            = false
                cdLabel.Parent             = bg

                task.spawn(function()
                    while bg.Parent do
                        local char = localPlayer.Character
                        if not char then task.wait(0.5); continue end
                        local abilityId = item.AbilityId or item.Id
                        local cdTag = char:GetAttribute("CD_" .. abilityId) :: number?

                        if cdTag and cdTag > tick() then
                            local remaining = cdTag - tick()
                            -- Logic: server sets CD to total time. We need the "started at" to do a proper percentage.
                            -- For now, we'll assume a standard 5s if we don't know, or just show the text.
                            -- Better: The server provides "Cooldown" in the item data.
                            local totalCd = item.Cooldown or 5
                            local progress = math.clamp(remaining / totalCd, 0, 1)

                            cdOverlay.Visible = true
                            cdOverlay.Size    = UDim2.fromScale(1, progress)
                            cdOverlay.Position = UDim2.fromScale(0, 0) -- Stays at top, fills downwards

                            cdLabel.Visible = true
                            cdLabel.Text    = string.format("%.1f", remaining)
                        else
                            cdOverlay.Visible = false
                            cdLabel.Visible   = false
                        end
                        task.wait(0.05)
                    end
                end)
            end

            -- "HELD" indicator — small dot bottom-left when weapon is drawn
            if isHeld then
                local dot = Instance.new("Frame")
                dot.Size             = UDim2.fromOffset(4, 4)
                dot.Position         = UDim2.new(0, 4, 1, -8)
                dot.BackgroundColor3 = catCol :: Color3
                dot.BorderSizePixel  = 0
                dot.Parent           = bg
                _corner(dot, 2)
            end

            -- Item name
            local nameL = Instance.new("TextLabel")
            nameL.Size         = UDim2.new(1, -4, 1, -18)
            nameL.Position     = UDim2.fromOffset(2, 4)
            nameL.BackgroundTransparency = 1
            nameL.TextColor3   = isHeld and PAL.TEXT_PRI or PAL.TEXT_SEC
            nameL.TextWrapped  = true
            nameL.TextScaled   = true
            nameL.Font         = Enum.Font.Antique
            nameL.Text         = item.Name or "?"
            nameL.Parent       = bg
        else
            -- Empty slot — barely visible inset border
            _stroke(bg, PAL.DIVIDER, 1, 0.7)
        end

        -- Slot number label below slot
        local numL = Instance.new("TextLabel")
        numL.Size           = UDim2.new(1, 0, 0, 16)
        numL.Position       = UDim2.new(0, 0, 1, 3)
        numL.BackgroundTransparency = 1
        numL.TextColor3     = item and PAL.TEXT_ACCENT or PAL.TEXT_DIM
        numL.TextSize       = 10
        numL.Font           = Enum.Font.Antique
        numL.Text           = tostring(slotIdx)
        numL.TextXAlignment = Enum.TextXAlignment.Center
        numL.Parent         = bg

        -- Transparent click/drag button
        local btn = Instance.new("TextButton")
        btn.Name               = "HBtn"..slotIdx
        btn.Size               = UDim2.fromOffset(SLOT_INNER, SLOT_INNER)
        btn.Position           = UDim2.fromOffset(x, 0)
        btn.BackgroundTransparency = 1
        btn.Text               = ""; btn.AutoButtonColor = false; btn.Parent = hotbar

        local cs, ci = slotIdx, item
        btn.MouseButton1Click:Connect(function()
            if ci then _onHotbarActivate(self, cs) end
        end)
        if ci then
            btn.MouseEnter:Connect(function()
                _showTooltip(self, ci)
            end)
            btn.MouseLeave:Connect(function()
                _hideTooltip(self, ci)
            end)
            btn.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    _startDrag(self, ci, "hotbar", cs)
                end
            end)
        end
    end

    if self._isOpen then
        hotbar.Size    = UDim2.fromOffset(HOTBAR_SLOTS * SLOT_OUTER, SLOT_INNER + 20)
        hotbar.Visible = true
        for i = 1, HOTBAR_SLOTS do
            _buildHotbarSlot(i-1, i, self._equipped[tostring(i)])
        end
    else
        if not hasAny then
            hotbar.Visible = false
        else
            local filled: {number} = {}
            for i = 1, HOTBAR_SLOTS do
                if self._equipped[tostring(i)] then table.insert(filled, i) end
            end
            hotbar.Size    = UDim2.fromOffset(#filled * SLOT_OUTER, SLOT_INNER + 20)
            hotbar.Visible = true
            for xi, si in ipairs(filled) do
                _buildHotbarSlot(xi-1, si, self._equipped[tostring(si)])
            end
        end
    end
end

-- ─── Toggle ───────────────────────────────────────────────────────────────────

function InventoryController:ToggleOpen()
    self._isOpen = not self._isOpen
    if self._hud then
        if self._isOpen then
            self._hud:HideHUD()
        else
            self._hud:ShowHUD()
        end
    end
    local root = self._invRoot :: Frame?
    if root then
        -- When open: stay at 0.02x (left). When closed: move to -0.4x (off-screen left)
        local xOffset = self._isOpen and 0.02 or -0.4
        TweenService:Create(root,
            TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Position = UDim2.new(xOffset, 0, 0.07, 0) }):Play()
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
        self._actionController  = dependencies.ActionController
        self._hud               = dependencies.PlayerHUDController
    end

    if self._aspectController then
        self._inventory = self._aspectController._inventory or {}
        self._equipped  = {}
        for slot, item in pairs(self._aspectController._equipped or {}) do
            self._equipped[tostring(slot)] = item
        end
        if self._aspectController.OnInventoryChanged then
            self._aspectController:OnInventoryChanged(function()
                self._inventory = self._aspectController._inventory or {}
                self._equipped  = {}
                for slot, item in pairs(self._aspectController._equipped or {}) do
                    self._equipped[tostring(slot)] = item
                end
                self:RefreshUI()
            end)
        end
    end

    -- Hotbar keys 1-8
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        for i, kc in ipairs(HOTBAR_KEYS) do
            if input.KeyCode == kc then _onHotbarActivate(self, i); return end
        end
    end)

    -- ` / I → toggle panel
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local kc = input.KeyCode
        local bt = kc == Enum.KeyCode.Backquote
            or (kc == Enum.KeyCode.Unknown
                and input.UserInputType == Enum.UserInputType.Keyboard
                and input.Character == "`")
        if bt or kc == Enum.KeyCode.I then self:ToggleOpen() end
    end)

    -- Tooltip following
    RunService.Heartbeat:Connect(function()
        if self._tooltipRoot and self._tooltipRoot.Visible then
            _positionTooltip(self)
        end
    end)

    self._initialized = true
    print("[InventoryController] Initialized")
end

function InventoryController:Start()
    print("[InventoryController] Started")
    _buildGui(self)
    self._isOpen = false
    self:RefreshUI()
end

return InventoryController
