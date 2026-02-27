--!strict
--[[
    InventoryController.lua — Deepwoken-style inventory + hotbar

    INTERACTION MODEL:
    ─ Inventory: drag only. No clicks. Drag item → drop on hotbar slot = equip.
    ─ Hotbar filled slot:
        • Weapons   → click = EquipWeapon (physically hold/draw the tool)
                      already held → click = UnequipWeapon (sheathe)
        • Abilities → click = UseItem (fire ability, stays slotted)
        • Others    → click = UnequipItem (return to inventory)
    ─ Hotbar filled slot: drag → drop on another slot = move/swap
    ─ Hotbar filled slot: drag → drop outside = unequip back to inventory
    ─ Hotbar empty slot:  shown when panel open, drag targets only
    ─ Active held-weapon slot glows white

    KEY DESIGN:
    ─ EquipItem  → moves item into a hotbar slot (server: profile.EquippedItems)
    ─ UnequipItem → removes item from hotbar slot back to inventory
    ─ EquipWeapon → tells WeaponService to physically hold the tool (in Character)
    ─ UnequipWeapon → tells WeaponService to sheathe the tool (to Backpack)
    ─ Weapons can live in ANY hotbar slot — slot number is irrelevant to WeaponService
    ─ EquipWeapon is NEVER sent on drag-to-slot, only on hotbar click

    DROP DETECTION: hit-tests actual rendered slot buttons (AbsolutePosition/Size)
    so compact hotbar (closed, only filled slots) maps correctly.
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
    "AspectMove", "Abilities",
    "Weapons", "Equipment", "Tools", "TrainingGear",
    "Consumables", "Relics", "Schematics", "QuestItems", "Materials",
}
local CATEGORY_DISPLAY = {
    AspectMove="Abilities", Abilities="Abilities", Weapons="Weapons",
    Equipment="Equipment", Tools="Tools", TrainingGear="Training Gear",
    Consumables="Consumables", Relics="Relics", Schematics="Schematics",
    QuestItems="Quest Items", Materials="Materials",
}
local CATEGORY_BG: {[string]: Color3} = {
    AspectMove=Color3.fromRGB(42,38,68),   Abilities=Color3.fromRGB(42,38,68),
    Weapons=Color3.fromRGB(62,34,34),      Equipment=Color3.fromRGB(36,52,62),
    Tools=Color3.fromRGB(52,48,32),        TrainingGear=Color3.fromRGB(36,58,38),
    Consumables=Color3.fromRGB(58,48,28),  Relics=Color3.fromRGB(32,42,62),
    Schematics=Color3.fromRGB(36,54,44),   QuestItems=Color3.fromRGB(42,42,52),
    Materials=Color3.fromRGB(48,48,48),
}
local RARITY_STROKE: {[string]: Color3} = {
    Common=Color3.fromRGB(110,110,110),   Uncommon=Color3.fromRGB(80,190,60),
    Rare=Color3.fromRGB(60,130,220),      Legendary=Color3.fromRGB(210,150,20),
    Potion=Color3.fromRGB(170,70,200),    Elemental=Color3.fromRGB(60,200,200),
}

local HOTBAR_SIZE    = 8
local SLOT_PX        = 48
local SLOT_PAD       = 6
local DRAG_THRESHOLD = 6   -- px before press becomes drag

local ACTIVE_STROKE  = Color3.fromRGB(255, 248, 180)
local ACTIVE_TINT    = Color3.fromRGB(255, 255, 200)

for _, cat in ipairs(CATEGORY_ORDER) do
    if InventoryController._collapsed[cat] == nil then
        InventoryController._collapsed[cat] = false
    end
end

-- ─── Data helpers ─────────────────────────────────────────────────────────────

-- Strip "weapon_" prefix — WeaponRegistry uses bare ids ("fists"), not "weapon_fists"
local function _toReg(id: string): string
    return (id:gsub("^weapon_", ""))
end

local function _isAbility(cat: string): boolean
    return cat == "AspectMove" or cat == "Abilities"
end

-- Live equipped map from AspectController (server-authoritative, updated on InventorySync)
local function _equipped(): {[string]: any}
    local ac = InventoryController._aspectController
    return (ac and ac._equipped) or {}
end

local function _equippedIdSet(): {[string]: boolean}
    local s = {}
    for _, v in pairs(_equipped()) do if v then s[v.Id] = true end end
    return s
end

-- Look up an item by id in both inventory and equipped slots
local function _findItem(id: string): any
    local ac  = InventoryController._aspectController
    local inv = (ac and ac:GetInventory()) or {}
    for _, v in ipairs(inv) do if v.Id == id then return v end end
    for _, v in pairs(_equipped()) do if v and v.Id == id then return v end end
    return nil
end

-- WeaponId attribute of any Tool currently held in Character (not Backpack)
local function _heldRegId(): string?
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

-- ─── UI factories ─────────────────────────────────────────────────────────────

local function _corner(p: Instance, r: number)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p
end
local function _stroke(p: Instance, t: number, col: Color3): UIStroke
    local s = Instance.new("UIStroke")
    s.Thickness = t; s.Color = col
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p
    return s
end

-- ─── Network ──────────────────────────────────────────────────────────────────

local function _net(): any return InventoryController._networkController end

-- Move item into a hotbar slot (InventoryService: profile.EquippedItems[slot] = item)
-- Does NOT send EquipWeapon — that's only done when the player clicks to hold.
local function _sendEquipItem(slot: number, itemId: string)
    if not _net() then return end
    _net():SendToServer("EquipItem", { Slot = tostring(slot), ItemId = itemId })
end

-- Remove item from slot → back to inventory
-- For weapons: also sends UnequipWeapon if that weapon is currently held
local function _sendUnequipItem(slot: number)
    if not _net() then return end
    local item = _equipped()[tostring(slot)]
    _net():SendToServer("UnequipItem", { Slot = tostring(slot) })
    if item and item.Category == "Weapons" then
        local reg = _toReg(item.Id)
        if _heldRegId() == reg then
            -- weapon is physically held — sheathe it via WeaponService
            _net():SendToServer("UnequipWeapon", {})
        end
    end
end

-- Tell WeaponService to physically hold (draw) a weapon.
-- The weapon must already be in the player's backpack (given by WeaponService on spawn
-- or on first EquipWeapon call). Sends a swap if a different weapon is currently held.
local function _sendEquipWeapon(itemId: string)
    if not _net() then return end
    _net():SendToServer("EquipWeapon", { WeaponId = _toReg(itemId) })
end

-- Tell WeaponService to sheathe the currently held weapon (move to Backpack)
local function _sendUnequipWeapon()
    if not _net() then return end
    _net():SendToServer("UnequipWeapon", {})
end

-- Fire an ability (stays in hotbar slot)
local function _useAbility(itemId: string)
    if not _net() then return end
    _net():SendToServer("UseItem", { ItemId = itemId })
end

-- ─── Drag system ──────────────────────────────────────────────────────────────

local dragging: { item: any, origin: string, slot: number? }? = nil

-- Hit-test every rendered Slot_N button by actual AbsolutePosition/Size.
-- This is correct even when the hotbar is compact (closed, non-contiguous slots).
local function _slotAt(mousePos: Vector2): number?
    local gui = InventoryController._gui
    if not gui then return nil end
    local hotbar = gui:FindFirstChild("HotbarRoot") :: Frame?
    if not hotbar then return nil end
    for _, child in hotbar:GetChildren() do
        if child:IsA("GuiObject") and child.Name:sub(1,5) == "Slot_" then
            local ap = child.AbsolutePosition
            local as = child.AbsoluteSize
            if mousePos.X >= ap.X and mousePos.X <= ap.X + as.X
            and mousePos.Y >= ap.Y and mousePos.Y <= ap.Y + as.Y then
                local n = tonumber(child.Name:sub(6))
                if n then return n end
            end
        end
    end
    return nil
end

local function _finishDrag(drag: typeof(dragging), mousePos: Vector2)
    if not drag then return end
    local targetSlot = _slotAt(mousePos)
    if targetSlot then
        if drag.origin == "inventory" then
            -- Drag from inventory → hotbar slot: equip into that slot
            _sendEquipItem(targetSlot, drag.item.Id)
        elseif drag.origin == "hotbar" and drag.slot and drag.slot ~= targetSlot then
            -- Drag hotbar → different hotbar slot: move (SetEquipped handles swap)
            _sendEquipItem(targetSlot, drag.item.Id)
        end
    else
        -- Dropped outside hotbar
        if drag.origin == "hotbar" and drag.slot then
            _sendUnequipItem(drag.slot)
        end
    end
end

local function _launchGhost(srcBtn: TextButton, item: any, origin: string, slot: number?, startPos: Vector2)
    if dragging then return end
    dragging = { item = item, origin = origin, slot = slot }

    local ghost = srcBtn:Clone() :: TextButton
    ghost.Name                   = "DragGhost"
    ghost.Parent                 = InventoryController._gui
    ghost.ZIndex                 = 1000
    ghost.AnchorPoint            = Vector2.new(0.5, 0.5)
    ghost.BackgroundTransparency = 0.3
    ghost.Size                   = UDim2.new(0, SLOT_PX, 0, SLOT_PX)
    ghost.Position               = UDim2.new(0, startPos.X, 0, startPos.Y)
    ghost.Active                 = false  -- don't intercept input while dragging

    local mc: RBXScriptConnection
    local uc: RBXScriptConnection
    mc = UserInputService.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then
            ghost.Position = UDim2.new(0, i.Position.X, 0, i.Position.Y)
        end
    end)
    uc = UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        mc:Disconnect(); uc:Disconnect()
        ghost:Destroy()
        local d = dragging; dragging = nil
        _finishDrag(d, UserInputService:GetMouseLocation())
    end)
end

-- Registry of draggable buttons: maps button → {item, origin, slot, onClickFn}
local _dragTargets: {[TextButton]: {item: any, origin: string, slot: number?, onClick: (() -> ())?}} = {}

local function _wireDrag(btn: TextButton, item: any, origin: string, slot: number?, onClickFn: (() -> ())?)
    _dragTargets[btn] = { item = item, origin = origin, slot = slot, onClick = onClickFn }
end

-- Global mouse handler: on LMB down, hit-test all registered drag targets.
-- This avoids ScrollingFrame eating InputBegan on children.
local _globalInputWired = false
local function _wireGlobalInput()
    if _globalInputWired then return end
    _globalInputWired = true

    UserInputService.InputBegan:Connect(function(input, _gp)
        -- Do NOT check _gp here. Clicks on GUI elements have gp=true, but we
        -- still need to detect them for our own drag hit-testing.
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if dragging then return end

        local mousePos = UserInputService:GetMouseLocation()

        -- Find which registered drag target (if any) the mouse is over
        local hitBtn: TextButton? = nil
        local hitInfo: typeof(_dragTargets[nil :: any]) = nil :: any
        for btn, info in _dragTargets do
            if not btn:IsDescendantOf(game) then continue end  -- stale ref
            local ap = btn.AbsolutePosition
            local as = btn.AbsoluteSize
            if mousePos.X >= ap.X and mousePos.X <= ap.X + as.X
            and mousePos.Y >= ap.Y and mousePos.Y <= ap.Y + as.Y then
                hitBtn  = btn
                hitInfo = info
                break
            end
        end
        if not hitBtn or not hitInfo then return end

        local pressPos = mousePos
        local didDrag  = false
        local mc: RBXScriptConnection
        local uc: RBXScriptConnection

        mc = UserInputService.InputChanged:Connect(function(i)
            if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            if not didDrag
            and (UserInputService:GetMouseLocation() - pressPos).Magnitude >= DRAG_THRESHOLD then
                didDrag = true
                mc:Disconnect(); uc:Disconnect()
                _launchGhost(hitBtn :: TextButton, hitInfo.item, hitInfo.origin,
                    hitInfo.slot, UserInputService:GetMouseLocation())
            end
        end)

        uc = UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            mc:Disconnect(); uc:Disconnect()
            if not didDrag and hitInfo.onClick then hitInfo.onClick() end
        end)
    end)
end

-- ─── GUI bootstrap ────────────────────────────────────────────────────────────

local function _ensureGui(): ScreenGui
    if InventoryController._gui then return InventoryController._gui :: ScreenGui end

    local sg = Instance.new("ScreenGui")
    sg.Name = "InventoryUI"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = false
    sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

    -- Panel
    local root = Instance.new("Frame")
    root.Name = "InventoryRoot"
    root.Size = UDim2.new(0, 310, 0, 440)
    root.Position = UDim2.new(1, -320, 0.08, 0)
    root.BackgroundColor3 = Color3.fromRGB(18, 18, 24); root.BorderSizePixel = 0
    root.Parent = sg; _corner(root, 10); _stroke(root, 1, Color3.fromRGB(55, 55, 80))

    local acc = Instance.new("Frame")  -- accent bar
    acc.Size = UDim2.new(1, -20, 0, 2); acc.Position = UDim2.new(0, 10, 0, 0)
    acc.BackgroundColor3 = Color3.fromRGB(120, 100, 200)
    acc.BorderSizePixel = 0; acc.Parent = root; _corner(acc, 2)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -14, 0, 30); title.Position = UDim2.new(0, 12, 0, 6)
    title.BackgroundTransparency = 1; title.Text = "INVENTORY"
    title.TextColor3 = Color3.fromRGB(200, 200, 220)
    title.Font = Enum.Font.GothamBold; title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = root

    local closeHint = Instance.new("TextLabel")
    closeHint.Size = UDim2.new(0, 70, 0, 16); closeHint.Position = UDim2.new(1, -78, 0, 10)
    closeHint.BackgroundTransparency = 1; closeHint.Text = "[I] close"
    closeHint.TextColor3 = Color3.fromRGB(90, 90, 120)
    closeHint.Font = Enum.Font.Gotham; closeHint.TextSize = 10
    closeHint.TextXAlignment = Enum.TextXAlignment.Right; closeHint.Parent = root

    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -20, 0, 1); div.Position = UDim2.new(0, 10, 0, 38)
    div.BackgroundColor3 = Color3.fromRGB(45, 45, 65); div.BorderSizePixel = 0; div.Parent = root

    local sf = Instance.new("Frame")
    sf.Name = "StatsFrame"; sf.Size = UDim2.new(1, 0, 0, 18)
    sf.Position = UDim2.new(0, 0, 0, 42); sf.BackgroundTransparency = 1; sf.Parent = root
    InventoryController._statsFrame = sf
    local sl = Instance.new("TextLabel")
    sl.Name = "StatsLabel"; sl.Size = UDim2.new(1, -12, 1, 0)
    sl.Position = UDim2.new(0, 12, 0, 0); sl.BackgroundTransparency = 1
    sl.Text = "0 items"; sl.TextColor3 = Color3.fromRGB(100, 100, 130)
    sl.Font = Enum.Font.Gotham; sl.TextSize = 10
    sl.TextXAlignment = Enum.TextXAlignment.Left; sl.Parent = sf

    local sb = Instance.new("TextBox")
    sb.Name = "SearchBox"; sb.Size = UDim2.new(1, -16, 0, 24)
    sb.Position = UDim2.new(0, 8, 0, 62)
    sb.BackgroundColor3 = Color3.fromRGB(28, 28, 38); sb.BorderSizePixel = 0
    sb.PlaceholderText = "Search..."; sb.Text = ""
    sb.TextColor3 = Color3.fromRGB(200, 200, 220)
    sb.PlaceholderColor3 = Color3.fromRGB(70, 70, 95)
    sb.Font = Enum.Font.Gotham; sb.TextSize = 11
    sb.ClearTextOnFocus = false; sb.Parent = root
    _corner(sb, 5); _stroke(sb, 1, Color3.fromRGB(50, 50, 75))
    sb:GetPropertyChangedSignal("Text"):Connect(function()
        InventoryController._search = string.lower(sb.Text)
        InventoryController:RefreshUI()
    end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Scroll"; scroll.Size = UDim2.new(1, -8, 1, -94)
    scroll.Position = UDim2.new(0, 4, 0, 90); scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 100)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.Parent = root

    -- Hotbar
    local hotbar = Instance.new("Frame")
    hotbar.Name = "HotbarRoot"; hotbar.AnchorPoint = Vector2.new(0.5, 1)
    hotbar.Size = UDim2.new(0, (SLOT_PX+SLOT_PAD)*HOTBAR_SIZE - SLOT_PAD + 16, 0, SLOT_PX+20)
    hotbar.Position = UDim2.new(0.5, 0, 1, -10)
    hotbar.BackgroundColor3 = Color3.fromRGB(14, 14, 20); hotbar.BorderSizePixel = 0
    hotbar.Parent = sg; _corner(hotbar, 8); _stroke(hotbar, 1, Color3.fromRGB(50, 50, 75))

    local hint = Instance.new("TextLabel")
    hint.Name = "Hint"; hint.Size = UDim2.new(0, 140, 0, 16)
    hint.Position = UDim2.new(0.5, -70, 0, 3); hint.BackgroundTransparency = 1
    hint.Text = "[I] inventory"; hint.TextColor3 = Color3.fromRGB(75, 75, 105)
    hint.Font = Enum.Font.Gotham; hint.TextSize = 10
    hint.Visible = not InventoryController._isOpen; hint.Parent = sg

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

    -- Clear stale drag targets (buttons are about to be destroyed and recreated)
    table.clear(_dragTargets)

    -- Stats bar
    local inv      = self._aspectController and self._aspectController:GetInventory() or {}
    local eqIds    = _equippedIdSet()
    local eqCount  = 0
    for _ in pairs(_equipped()) do eqCount += 1 end
    local sl = self._statsFrame and (self._statsFrame :: Frame):FindFirstChild("StatsLabel") :: TextLabel?
    if sl then sl.Text = string.format("%d items  •  %d slotted", #inv, eqCount) end

    -- Clear scroll
    for _, c in scroll:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end

    -- Filter: hide hotbarred items + search
    local filtered: {any} = {}
    for _, item in ipairs(inv) do
        if eqIds[item.Id] then continue end
        if self._search ~= ""
        and not string.find(string.lower(item.Name or ""), self._search, 1, true) then continue end
        table.insert(filtered, item)
    end

    local cols   = 5
    local y      = 4
    local heldId = _heldRegId()

    -- ── Inventory grid ───────────────────────────────────────────────────────
    for _, cat in ipairs(CATEGORY_ORDER) do
        local catItems: {any} = {}
        for _, item in ipairs(filtered) do
            if item.Category == cat then table.insert(catItems, item) end
        end
        if #catItems == 0 then continue end

        local hdrBg = CATEGORY_BG[cat] or Color3.fromRGB(40,40,55)
        local hdr   = Instance.new("TextButton")
        hdr.Name = "Hdr_"..cat; hdr.Size = UDim2.new(1,-6,0,20)
        hdr.Position = UDim2.new(0,3,0,y); hdr.BackgroundColor3 = hdrBg
        hdr.BorderSizePixel = 0; hdr.AutoButtonColor = false
        hdr.Text = (self._collapsed[cat] and "▶  " or "▼  ")
            .. (CATEGORY_DISPLAY[cat] or cat) .. "  (" .. #catItems .. ")"
        hdr.TextXAlignment = Enum.TextXAlignment.Left
        hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 10
        hdr.TextColor3 = Color3.fromRGB(180,180,210); hdr.Parent = scroll
        _corner(hdr, 4)
        hdr.MouseButton1Click:Connect(function()
            self._collapsed[cat] = not self._collapsed[cat]; self:RefreshUI()
        end)
        hdr.MouseEnter:Connect(function()
            hdr.BackgroundColor3 = Color3.fromRGB(
                math.min(hdrBg.R*255+15,255),math.min(hdrBg.G*255+15,255),math.min(hdrBg.B*255+15,255))
        end)
        hdr.MouseLeave:Connect(function() hdr.BackgroundColor3 = hdrBg end)
        y += 24

        if not self._collapsed[cat] then
            local col, row = 0, 0
            for _, item in ipairs(catItems) do
                local tileBg    = CATEGORY_BG[cat] or Color3.fromRGB(40,40,55)
                local rarityCol = RARITY_STROKE[item.Rarity or "Common"] or Color3.fromRGB(110,110,110)

                local tile = Instance.new("TextButton")
                tile.Name = "Inv_"..item.Id
                tile.Size = UDim2.new(0,SLOT_PX,0,SLOT_PX)
                tile.Position = UDim2.new(0, 3+col*(SLOT_PX+SLOT_PAD), 0, y+row*(SLOT_PX+SLOT_PAD))
                tile.BackgroundColor3 = tileBg; tile.BorderSizePixel = 0
                tile.Text = ""; tile.AutoButtonColor = false
                tile.Parent = scroll; _corner(tile, 5); _stroke(tile, 1.5, rarityCol)

                -- name strip
                local ns = Instance.new("Frame")
                ns.Size = UDim2.new(1,0,0,15); ns.Position = UDim2.new(0,0,1,-15)
                ns.BackgroundColor3 = Color3.fromRGB(0,0,0); ns.BackgroundTransparency = 0.45
                ns.BorderSizePixel = 0; ns.Parent = tile; _corner(ns, 3)
                local nl = Instance.new("TextLabel")
                nl.Size = UDim2.new(1,-4,1,0); nl.Position = UDim2.new(0,2,0,0)
                nl.BackgroundTransparency = 1; nl.Text = item.Name or item.Id
                nl.TextColor3 = Color3.fromRGB(210,210,230)
                nl.Font = Enum.Font.Gotham; nl.TextSize = 9
                nl.TextTruncate = Enum.TextTruncate.AtEnd; nl.Parent = ns

                tile.MouseEnter:Connect(function()
                    tile.BackgroundColor3 = Color3.fromRGB(
                        math.min(tileBg.R*255+12,255),math.min(tileBg.G*255+12,255),math.min(tileBg.B*255+12,255))
                end)
                tile.MouseLeave:Connect(function() tile.BackgroundColor3 = tileBg end)

                -- DRAG ONLY — no click handler in inventory
                _wireDrag(tile, item, "inventory", nil, nil)

                col += 1
                if col >= cols then col = 0; row += 1 end
            end
            y += (row+1)*(SLOT_PX+SLOT_PAD) + 6
        end
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, y+8)

    -- ── Hotbar ────────────────────────────────────────────────────────────────
    local hotbar = gui:FindFirstChild("HotbarRoot") :: Frame?
    if not hotbar then return end
    for _, c in hotbar:GetChildren() do
        if c:IsA("GuiObject") then c:Destroy() end
    end

    local slots: {[number]: any} = {}
    for k, v in pairs(_equipped()) do
        local n = tonumber(k); if n then slots[n] = v end
    end

    -- Compact when closed (only filled slots); full 8 when open
    local toRender: {number} = {}
    for i = 1, HOTBAR_SIZE do
        if self._isOpen or slots[i] then table.insert(toRender, i) end
    end

    local vc  = #toRender
    local hbW = vc * SLOT_PX + math.max(0, vc-1) * SLOT_PAD + 16
    hotbar.Size = UDim2.new(0, hbW, 0, SLOT_PX+20)

    local rx = 8
    for _, idx in ipairs(toRender) do
        local item     = slots[idx]
        local isWeapon = item and item.Category == "Weapons"
        local regId    = isWeapon and _toReg(item.Id) or nil
        local isHeld   = regId ~= nil and regId == heldId
        local tileBg   = item and (CATEGORY_BG[item.Category] or Color3.fromRGB(40,40,55))
            or Color3.fromRGB(22,22,32)

        local btn = Instance.new("TextButton")
        btn.Name = "Slot_"..idx  -- must be "Slot_N" for _slotAt() hit-test
        btn.Size = UDim2.new(0,SLOT_PX,0,SLOT_PX)
        btn.Position = UDim2.new(0,rx,0,10)
        btn.BackgroundColor3 = tileBg; btn.BorderSizePixel = 0
        btn.Text = ""; btn.AutoButtonColor = false; btn.Parent = hotbar
        _corner(btn, 5)

        -- Stroke: white glow for held weapon, rarity for filled, dim for empty
        if isHeld then
            _stroke(btn, 2.5, ACTIVE_STROKE)
            local glow = Instance.new("Frame")
            glow.Size = UDim2.new(1,0,1,0); glow.BackgroundColor3 = ACTIVE_TINT
            glow.BackgroundTransparency = 0.88; glow.BorderSizePixel = 0
            glow.ZIndex = btn.ZIndex; glow.Parent = btn; _corner(glow, 5)
        elseif item then
            _stroke(btn, 1.5, RARITY_STROKE[item.Rarity or "Common"] or Color3.fromRGB(110,110,110))
        else
            _stroke(btn, 1, Color3.fromRGB(38,38,58))
        end

        -- Slot number (top-left)
        local num = Instance.new("TextLabel")
        num.Size = UDim2.new(0,14,0,14); num.Position = UDim2.new(0,2,0,1)
        num.BackgroundTransparency = 1; num.Text = tostring(idx)
        num.Font = Enum.Font.GothamBold; num.TextSize = 9
        num.TextColor3 = isHeld and Color3.fromRGB(255,248,180)
            or (item and Color3.fromRGB(140,140,170) or Color3.fromRGB(55,55,80))
        num.Parent = btn

        if item then
            -- Name strip
            local ns = Instance.new("Frame")
            ns.Size = UDim2.new(1,0,0,15); ns.Position = UDim2.new(0,0,1,-15)
            ns.BackgroundColor3 = Color3.fromRGB(0,0,0); ns.BackgroundTransparency = 0.45
            ns.BorderSizePixel = 0; ns.Parent = btn; _corner(ns, 3)
            local nl = Instance.new("TextLabel")
            nl.Size = UDim2.new(1,-4,1,0); nl.Position = UDim2.new(0,2,0,0)
            nl.BackgroundTransparency = 1; nl.Text = item.Name or item.Id
            nl.TextColor3 = Color3.fromRGB(210,210,230)
            nl.Font = Enum.Font.Gotham; nl.TextSize = 9
            nl.TextTruncate = Enum.TextTruncate.AtEnd; nl.Parent = ns

            btn.MouseEnter:Connect(function()
                btn.BackgroundColor3 = Color3.fromRGB(
                    math.min(tileBg.R*255+14,255),math.min(tileBg.G*255+14,255),math.min(tileBg.B*255+14,255))
            end)
            btn.MouseLeave:Connect(function() btn.BackgroundColor3 = tileBg end)

            -- Capture for closures
            local ci  = idx
            local cit = item

            -- Click handler — different per category
            local onClickFn: () -> ()
            if _isAbility(cit.Category) then
                -- Abilities: fire immediately, stay in slot
                onClickFn = function() _useAbility(cit.Id) end
            elseif cit.Category == "Weapons" then
                -- Weapons: toggle hold/sheathe
                -- Click = draw weapon (EquipWeapon) or sheathe (UnequipWeapon)
                onClickFn = function()
                    local reg = _toReg(cit.Id)
                    if _heldRegId() == reg then
                        _sendUnequipWeapon()
                    else
                        _sendEquipWeapon(cit.Id)
                    end
                end
            else
                -- Everything else: click = unequip back to inventory
                onClickFn = function() _sendUnequipItem(ci) end
            end

            _wireDrag(btn, cit, "hotbar", ci, onClickFn)
        end

        rx += SLOT_PX + SLOT_PAD
    end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function InventoryController:Init(dependencies: {[string]: any}?)
    print("[InventoryController] Initializing...")
    if dependencies then
        self._aspectController  = dependencies.AspectController
        self._networkController = dependencies.NetworkController
    end
    if self._aspectController and self._aspectController.OnInventoryChanged then
        self._aspectController:OnInventoryChanged(function() self:RefreshUI() end)
    end

    -- Wire global LMB handler for drag (works through ScrollingFrames)
    _wireGlobalInput()

    -- I / backtick → toggle panel
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local kc = input.KeyCode
        local isTick = kc == Enum.KeyCode.Backquote
            or (kc == Enum.KeyCode.Unknown
                and input.UserInputType == Enum.UserInputType.Keyboard
                and (input :: any).Character == "`")
        if isTick or kc == Enum.KeyCode.I then self:ToggleOpen() end
    end)

    -- Watch character for tool held/unhold events → update active glow
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
        TweenService:Create(root,
            TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Position = self._isOpen
                and UDim2.new(1, -320, 0.08, 0)
                or  UDim2.new(1,   10, 0.08, 0) }):Play()
    end
    local hint = gui:FindFirstChild("Hint") :: TextLabel?
    if hint then hint.Visible = not self._isOpen end
    self:RefreshUI()
end

return InventoryController