--!strict
--[[
    Class: ProgressionController
    Description: Client-side progression state management.
                 Handles Resonance display, stat allocation UI, and Ring cap feedback.

    Issue #138: ProgressionService client sync
    Issue #140: Stat-based progression — replace Discipline lock-in with free stat allocation
    Epic #51: Phase 4 — World & Narrative

    Dependencies: NetworkController

    Public API:
        ProgressionController:GetState() -> ProgressionState
        ProgressionController:AllocateStat(statName, amount)   -- sends to server
        ProgressionController:OpenStatPanel()                   -- shows UI
        ProgressionController:CloseStatPanel()                  -- hides UI
        ProgressionController._resonanceListeners               -- table of callbacks for HUD updates
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local NetworkController = require(script.Parent.NetworkController)

-- ─── Types ────────────────────────────────────────────────────────────────────

type StatTable = {
    Strength:     number,
    Fortitude:    number,
    Agility:      number,
    Intelligence: number,
    Willpower:    number,
    Charisma:     number,
}

type ProgressionState = {
    TotalResonance:  number,
    ResonanceShards: number,
    CurrentRing:     number,
    SoftCap:         number,   -- -1 = no cap
    IsSoftCapped:    boolean,
    DisciplineId:    string,
    OmenMarks:       number,
    StatPoints:      number,
    Stats:           StatTable,
}

-- ─── Constants ────────────────────────────────────────────────────────────────

local STAT_DISPLAY_ORDER: {string} = {
    "Strength", "Fortitude", "Agility", "Intelligence", "Willpower", "Charisma"
}

local STAT_UI_LABELS: {[string]: string} = {
    Strength     = "STR",
    Fortitude    = "FOR",
    Agility      = "AGI",
    Intelligence = "INT",
    Willpower    = "WIL",
    Charisma     = "CHA",
}

local STAT_UI_EFFECTS: {[string]: string} = {
    Strength     = "+5 HP / +2 Break",
    Fortitude    = "+6 Posture / +0.2 Posture Recovery",
    Agility      = "Phase 4+",
    Intelligence = "+8 Mana / +0.3 Regen",
    Willpower    = "+4 Mana / +0.1 Regen",
    Charisma     = "Phase 4+",
}

-- Toggle keybind — P key opens/closes the stat panel
local PANEL_KEYBIND = Enum.KeyCode.P

-- ─── Module State ─────────────────────────────────────────────────────────────

local ProgressionController = {}
ProgressionController._initialized = false

-- Cached progression state (updated by server events)
local _state: ProgressionState = {
    TotalResonance  = 0,
    ResonanceShards = 0,
    CurrentRing     = 1,
    SoftCap         = 2000,
    IsSoftCapped    = false,
    DisciplineId    = "Wayward",
    OmenMarks       = 0,
    StatPoints      = 0,
    Stats = {
        Strength     = 0,
        Fortitude    = 0,
        Agility      = 0,
        Intelligence = 0,
        Willpower    = 0,
        Charisma     = 0,
    },
}

-- Listeners notified on any state change (HUD, debug panels, etc.)
ProgressionController._resonanceListeners = {} :: {(state: ProgressionState) -> ()}

-- Active stat panel ScreenGui reference
local _statPanelGui: ScreenGui? = nil

-- Per-stat count labels (refreshed on StatAllocated / ProgressionSync)
local _statValueLabels: {[string]: TextLabel} = {}

-- Points remaining label (refreshed on updates)
local _pointsLabel: TextLabel? = nil

-- ─── Stat Allocation UI ───────────────────────────────────────────────────────

local function _refreshStatUI()
    for statName, label in pairs(_statValueLabels) do
        local v = _state.Stats[statName] or 0
        label.Text = tostring(v) .. " / 20"
    end
    if _pointsLabel then
        _pointsLabel.Text = "Unspent Points: " .. _state.StatPoints
    end
end

local function _buildStatPanel()
    if _statPanelGui then return end  -- already open

    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name          = "StatAllocationGui"
    gui.ResetOnSpawn  = false
    gui.DisplayOrder  = 90
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent        = player.PlayerGui

    -- Panel background
    local PANEL_W, PANEL_H = 360, 60 + 52 * #STAT_DISPLAY_ORDER + 48
    local panel = Instance.new("Frame")
    panel.AnchorPoint        = Vector2.new(1, 0.5)
    panel.Position           = UDim2.fromScale(0.97, 0.5)
    panel.Size               = UDim2.fromOffset(PANEL_W, PANEL_H)
    panel.BackgroundColor3   = Color3.fromRGB(12, 12, 18)
    panel.BackgroundTransparency = 0.10
    panel.BorderSizePixel    = 0
    panel.ZIndex             = 2
    panel.Parent             = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", panel).Color        = Color3.fromRGB(60, 55, 80)

    -- Title
    local titleLbl = Instance.new("TextLabel")
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text       = "STAT ALLOCATION  [P]"
    titleLbl.Size       = UDim2.new(1, -12, 0, 36)
    titleLbl.Position   = UDim2.fromOffset(12, 10)
    titleLbl.Font       = Enum.Font.GothamBold
    titleLbl.TextColor3 = Color3.fromRGB(220, 200, 160)
    titleLbl.TextSize   = 16
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.ZIndex     = 3
    titleLbl.Parent     = panel

    -- Points remaining
    local pointsLbl = Instance.new("TextLabel")
    pointsLbl.BackgroundTransparency = 1
    pointsLbl.Text       = "Unspent Points: 0"
    pointsLbl.Size       = UDim2.new(1, -12, 0, 22)
    pointsLbl.Position   = UDim2.fromOffset(12, 38)
    pointsLbl.Font       = Enum.Font.Gotham
    pointsLbl.TextColor3 = Color3.fromRGB(180, 200, 140)
    pointsLbl.TextSize   = 13
    pointsLbl.TextXAlignment = Enum.TextXAlignment.Left
    pointsLbl.ZIndex     = 3
    pointsLbl.Parent     = panel
    _pointsLabel = pointsLbl

    -- Stat rows
    local ROW_Y_START = 62
    local ROW_H       = 52

    for i, statName in ipairs(STAT_DISPLAY_ORDER) do
        local rowY = ROW_Y_START + (i - 1) * ROW_H

        -- Row bg
        local rowBg = Instance.new("Frame")
        rowBg.Size             = UDim2.new(1, -16, 0, ROW_H - 4)
        rowBg.Position         = UDim2.fromOffset(8, rowY)
        rowBg.BackgroundColor3 = Color3.fromRGB(22, 20, 32)
        rowBg.BackgroundTransparency = 0.3
        rowBg.BorderSizePixel  = 0
        rowBg.ZIndex           = 2
        rowBg.Parent           = panel
        Instance.new("UICorner", rowBg).CornerRadius = UDim.new(0, 4)

        -- Stat abbreviation label
        local abbrevLbl = Instance.new("TextLabel")
        abbrevLbl.BackgroundTransparency = 1
        abbrevLbl.Text       = STAT_UI_LABELS[statName] or statName
        abbrevLbl.Size       = UDim2.fromOffset(44, 20)
        abbrevLbl.Position   = UDim2.fromOffset(8, 6)
        abbrevLbl.Font       = Enum.Font.GothamBold
        abbrevLbl.TextColor3 = Color3.fromRGB(220, 200, 255)
        abbrevLbl.TextSize   = 13
        abbrevLbl.TextXAlignment = Enum.TextXAlignment.Left
        abbrevLbl.ZIndex     = 3
        abbrevLbl.Parent     = rowBg

        -- Effect description
        local effectLbl = Instance.new("TextLabel")
        effectLbl.BackgroundTransparency = 1
        effectLbl.Text       = STAT_UI_EFFECTS[statName] or ""
        effectLbl.Size       = UDim2.fromOffset(196, 16)
        effectLbl.Position   = UDim2.fromOffset(52, 8)
        effectLbl.Font       = Enum.Font.Gotham
        effectLbl.TextColor3 = Color3.fromRGB(140, 135, 150)
        effectLbl.TextSize   = 11
        effectLbl.TextXAlignment = Enum.TextXAlignment.Left
        effectLbl.TextWrapped = true
        effectLbl.ZIndex     = 3
        effectLbl.Parent     = rowBg

        -- Current value / max
        local valueLbl = Instance.new("TextLabel")
        valueLbl.BackgroundTransparency = 1
        valueLbl.Text       = "0 / 20"
        valueLbl.Size       = UDim2.fromOffset(60, 20)
        valueLbl.Position   = UDim2.fromOffset(196, 6)
        valueLbl.Font       = Enum.Font.Code
        valueLbl.TextColor3 = Color3.fromRGB(180, 180, 140)
        valueLbl.TextSize   = 12
        valueLbl.TextXAlignment = Enum.TextXAlignment.Right
        valueLbl.ZIndex     = 3
        valueLbl.Parent     = rowBg
        _statValueLabels[statName] = valueLbl

        -- +1 button
        local plusBtn = Instance.new("TextButton")
        plusBtn.AnchorPoint = Vector2.new(1, 0.5)
        plusBtn.Position    = UDim2.new(1, -6, 0.5, 0)
        plusBtn.Size        = UDim2.fromOffset(30, 24)
        plusBtn.BackgroundColor3 = Color3.fromRGB(70, 60, 100)
        plusBtn.BorderSizePixel  = 0
        plusBtn.Text        = "+"
        plusBtn.Font        = Enum.Font.GothamBold
        plusBtn.TextColor3  = Color3.new(1, 1, 1)
        plusBtn.TextSize    = 16
        plusBtn.ZIndex      = 4
        plusBtn.Parent      = rowBg
        Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 4)

        local capturedStat = statName
        plusBtn.Activated:Connect(function()
            if _state.StatPoints > 0 and (_state.Stats[capturedStat] or 0) < 20 then
                ProgressionController:AllocateStat(capturedStat, 1)
            end
        end)
    end

    -- Discipline label at bottom
    local disciplineLbl = Instance.new("TextLabel")
    disciplineLbl.BackgroundTransparency = 1
    disciplineLbl.Text       = "Build: " .. (_state.DisciplineId or "Wayward")
    disciplineLbl.Name       = "DisciplineLabel"
    disciplineLbl.Size       = UDim2.new(1, -16, 0, 26)
    disciplineLbl.Position   = UDim2.fromOffset(8, ROW_Y_START + #STAT_DISPLAY_ORDER * ROW_H + 6)
    disciplineLbl.Font       = Enum.Font.GothamMedium
    disciplineLbl.TextColor3 = Color3.fromRGB(180, 160, 220)
    disciplineLbl.TextSize   = 13
    disciplineLbl.TextXAlignment = Enum.TextXAlignment.Left
    disciplineLbl.ZIndex     = 3
    disciplineLbl.Parent     = panel

    _statPanelGui = gui
    _refreshStatUI()
end

local function _destroyStatPanel()
    _statValueLabels = {}
    _pointsLabel = nil
    if _statPanelGui then
        _statPanelGui:Destroy()
        _statPanelGui = nil
    end
end

-- ─── State Helpers ────────────────────────────────────────────────────────────

local function _notifyListeners()
    for _, fn in ipairs(ProgressionController._resonanceListeners) do
        pcall(fn, _state)
    end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
    GetState() -> ProgressionState
    Returns a snapshot of the current local progression state.
]]
function ProgressionController:GetState(): ProgressionState
    return {
        TotalResonance  = _state.TotalResonance,
        ResonanceShards = _state.ResonanceShards,
        CurrentRing     = _state.CurrentRing,
        SoftCap         = _state.SoftCap,
        IsSoftCapped    = _state.IsSoftCapped,
        DisciplineId    = _state.DisciplineId,
        OmenMarks       = _state.OmenMarks,
        StatPoints      = _state.StatPoints,
        Stats           = {
            Strength     = _state.Stats.Strength,
            Fortitude    = _state.Stats.Fortitude,
            Agility      = _state.Stats.Agility,
            Intelligence = _state.Stats.Intelligence,
            Willpower    = _state.Stats.Willpower,
            Charisma     = _state.Stats.Charisma,
        },
    }
end

--[[
    AllocateStat(statName, amount)
    Sends a StatAllocate request to the server.
    Server is authoritative — local state updates when StatAllocated fires back.
]]
function ProgressionController:AllocateStat(statName: string, amount: number)
    NetworkController:SendToServer("StatAllocate", {
        StatName = statName,
        Amount   = amount,
    })
end

--[[
    OpenStatPanel()
    Shows the stat allocation ScreenGui.
]]
function ProgressionController:OpenStatPanel()
    _buildStatPanel()
end

--[[
    CloseStatPanel()
    Hides and destroys the stat allocation ScreenGui.
]]
function ProgressionController:CloseStatPanel()
    _destroyStatPanel()
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function ProgressionController:Init(dependencies)
    print("[ProgressionController] Initializing...")
    self._initialized = true
    print("[ProgressionController] Initialized")
end

function ProgressionController:Start()
    print("[ProgressionController] Starting...")

    -- Full state sync on join or relog
    NetworkController:RegisterHandler("ProgressionSync", function(packet: any)
        _state.TotalResonance  = packet.TotalResonance  or 0
        _state.ResonanceShards = packet.ResonanceShards or 0
        _state.CurrentRing     = packet.CurrentRing     or 1
        _state.SoftCap         = packet.SoftCap         or 2000
        _state.DisciplineId    = packet.DisciplineId    or "Wayward"
        _state.OmenMarks       = packet.OmenMarks       or 0
        _state.StatPoints      = packet.StatPoints       or 0
        _state.IsSoftCapped    = _state.SoftCap ~= -1
            and _state.TotalResonance >= _state.SoftCap

        -- Populate stats from packet (fallback to 0 per stat)
        local pkgStats = packet.Stats or {}
        _state.Stats.Strength     = pkgStats.Strength     or 0
        _state.Stats.Fortitude    = pkgStats.Fortitude    or 0
        _state.Stats.Agility      = pkgStats.Agility      or 0
        _state.Stats.Intelligence = pkgStats.Intelligence or 0
        _state.Stats.Willpower    = pkgStats.Willpower    or 0
        _state.Stats.Charisma     = pkgStats.Charisma     or 0

        print(("[ProgressionController] Sync — Ring %d  •  %d Resonance  •  %d Shards  •  %d StatPoints")
            :format(_state.CurrentRing, _state.TotalResonance, _state.ResonanceShards, _state.StatPoints))

        _refreshStatUI()
        _notifyListeners()
    end)

    -- Incremental Resonance update (combat rewards, etc.)
    NetworkController:RegisterHandler("ResonanceUpdate", function(packet: any)
        _state.TotalResonance  = packet.TotalResonance  or _state.TotalResonance
        _state.ResonanceShards = packet.ResonanceShards or _state.ResonanceShards
        _state.CurrentRing     = packet.CurrentRing     or _state.CurrentRing
        _state.SoftCap         = packet.SoftCap         or _state.SoftCap
        _state.IsSoftCapped    = packet.IsSoftCapped    == true

        -- StatPoints may be included when a milestone is reached
        if type(packet.StatPoints) == "number" then
            _state.StatPoints = packet.StatPoints
        end

        local delta  = packet.ShardDelta or 0
        local source = packet.Source     or "unknown"

        if delta > 0 then
            print(("[ProgressionController] +%d Shards from %s (total: %d)")
                :format(delta, source, _state.ResonanceShards))
            if _state.IsSoftCapped then
                warn("[ProgressionController] At Ring soft cap — venture to the next Ring to grow further")
            end
        elseif delta < 0 then
            print(("[ProgressionController] %d Shards lost on death (total: %d)")
                :format(delta, _state.ResonanceShards))
        end

        _refreshStatUI()
        _notifyListeners()
    end)

    -- Stat allocation confirmation from server
    NetworkController:RegisterHandler("StatAllocated", function(packet: any)
        local statName = packet.StatName
        if statName and _state.Stats[statName] ~= nil then
            _state.Stats[statName] = packet.NewAmount or _state.Stats[statName]
        end
        if type(packet.StatPoints) == "number" then
            _state.StatPoints = packet.StatPoints
        end
        if type(packet.DisciplineId) == "string" then
            local prev = _state.DisciplineId
            _state.DisciplineId = packet.DisciplineId
            if prev ~= _state.DisciplineId then
                print(("[ProgressionController] Build identity updated: %s → %s")
                    :format(prev, _state.DisciplineId))
                -- Update discipline label in panel if open
                if _statPanelGui then
                    local gui = _statPanelGui :: ScreenGui
                    local panel = gui:FindFirstChildOfClass("Frame")
                    if panel then
                        local label = panel:FindFirstChild("DisciplineLabel") :: TextLabel?
                        if label then label.Text = "Build: " .. _state.DisciplineId end
                    end
                end
            end
        end

        print(("[ProgressionController] StatAllocated: %s → %d (unspent: %d)")
            :format(statName or "?", packet.NewAmount or 0, _state.StatPoints))

        _refreshStatUI()
        _notifyListeners()
    end)

    -- Toggle stat panel with P key
    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then return end
        if input.KeyCode == PANEL_KEYBIND then
            if _statPanelGui then
                _destroyStatPanel()
            else
                _buildStatPanel()
            end
        end
    end)

    print("[ProgressionController] Started  (press P to open stat allocation panel)")
end

return ProgressionController