--!strict
--[[
    Class: ProgressionController
    Description: Client-side progression state management.
                 Handles Resonance display, Discipline selection UI, and Ring cap feedback.

    Issue #138: ProgressionService client sync
    Issue #139: Discipline selection UI
    Epic #51: Phase 4 — World & Narrative

    Dependencies: NetworkController, (PlayerHUDController — optional HUD integration)

    Public API:
        ProgressionController:GetState() -> ProgressionState
        ProgressionController._resonanceListeners  -- table of callbacks for HUD updates
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NetworkController = require(script.Parent.NetworkController)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)

-- ─── Types ────────────────────────────────────────────────────────────────────

type ProgressionState = {
    TotalResonance:      number,
    ResonanceShards:     number,
    CurrentRing:         number,
    SoftCap:             number,   -- -1 = no cap
    IsSoftCapped:        boolean,
    HasChosenDiscipline: boolean,
    DisciplineId:        string,
    OmenMarks:           number,
}

-- ─── Module State ─────────────────────────────────────────────────────────────

local ProgressionController = {}
ProgressionController._initialized = false

-- Cached progression state (updated by server events)
local _state: ProgressionState = {
    TotalResonance      = 0,
    ResonanceShards     = 0,
    CurrentRing         = 1,
    SoftCap             = 2000,
    IsSoftCapped        = false,
    HasChosenDiscipline = false,
    DisciplineId        = "Wayward",
    OmenMarks           = 0,
}

-- Listeners notified on any state change (HUD, debug panels, etc.)
ProgressionController._resonanceListeners = {} :: {(state: ProgressionState) -> ()}

-- Active discipline selection ScreenGui reference
local _disciplineGui: ScreenGui? = nil

-- ─── Discipline UI ────────────────────────────────────────────────────────────

local DISCIPLINE_INFO: {[string]: {Tagline: string, Stats: string, Color: Color3}} = {
    Wayward = {
        Tagline = "Balanced Adaptability",
        Stats   = "Medium pools • All weapon classes • No peaks, no gaps",
        Color   = Color3.fromRGB(160, 160, 200),
    },
    Ironclad = {
        Tagline = "Weight and Permanence",
        Stats   = "High Posture • Heavy weapons • Builds Poise from hits",
        Color   = Color3.fromRGB(200, 140, 80),
    },
    Silhouette = {
        Tagline = "Speed and Efficiency",
        Stats   = "High Breath • Light weapons • Ghoststep chain-dashes",
        Color   = Color3.fromRGB(120, 200, 160),
    },
    Resonant = {
        Tagline = "The Weapon as Instrument",
        Stats   = "Aspect amplification • Esoteric weapons • Hybrid melee-caster",
        Color   = Color3.fromRGB(180, 120, 220),
    },
}

local function _destroyDisciplineGui()
    if _disciplineGui then
        _disciplineGui:Destroy()
        _disciplineGui = nil
    end
end

local function _makeLabel(parent: Instance, props: {
    Text: string, Size: UDim2, Position: UDim2?,
    Font: Enum.Font?, TextColor3: Color3?, TextSize: number?,
    TextWrapped: boolean?, ZIndex: number?,
}): TextLabel
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Text        = props.Text
    lbl.Size        = props.Size
    lbl.Font        = props.Font or Enum.Font.GothamBold
    lbl.TextColor3  = props.TextColor3 or Color3.new(1, 1, 1)
    lbl.TextSize    = props.TextSize or 18
    lbl.TextWrapped = props.TextWrapped or false
    lbl.ZIndex      = props.ZIndex or 2
    if props.Position then lbl.Position = props.Position end
    lbl.Parent = parent
    return lbl
end

local function _buildDisciplineGui()
    _destroyDisciplineGui()

    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "DisciplineSelectionGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 100
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = player.PlayerGui

    -- Dark overlay
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.35
    overlay.ZIndex = 1
    overlay.Parent = gui

    -- Container
    local container = Instance.new("Frame")
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Position    = UDim2.fromScale(0.5, 0.5)
    container.Size        = UDim2.fromOffset(860, 440)
    container.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    container.BorderSizePixel  = 0
    container.ZIndex = 2
    container.Parent = gui
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

    -- Title
    _makeLabel(container, {
        Text      = "CHOOSE YOUR DISCIPLINE",
        Size      = UDim2.new(1, 0, 0, 44),
        Position  = UDim2.fromOffset(0, 18),
        Font      = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(220, 200, 160),
        TextSize  = 26,
        ZIndex    = 3,
    })

    _makeLabel(container, {
        Text      = "This choice is permanent. Disciplines can be cross-trained later at significant cost.",
        Size      = UDim2.new(1, -40, 0, 24),
        Position  = UDim2.fromOffset(20, 60),
        Font      = Enum.Font.Gotham,
        TextColor3 = Color3.fromRGB(160, 155, 145),
        TextSize  = 14,
        ZIndex    = 3,
    })

    -- Card row
    local cardRow = Instance.new("Frame")
    cardRow.Position = UDim2.fromOffset(20, 96)
    cardRow.Size     = UDim2.new(1, -40, 1, -116)
    cardRow.BackgroundTransparency = 1
    cardRow.ZIndex = 2
    cardRow.Parent = container

    local layout = Instance.new("UIListLayout", cardRow)
    layout.FillDirection  = Enum.FillDirection.Horizontal
    layout.Padding        = UDim.new(0, 12)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center

    local disciplines = {"Wayward", "Ironclad", "Silhouette", "Resonant"}

    for _, discId in ipairs(disciplines) do
        local info = DISCIPLINE_INFO[discId]
        local cfg  = DisciplineConfig[discId]

        local card = Instance.new("TextButton")
        card.Name  = discId
        card.Size  = UDim2.new(0.25, -9, 1, 0)
        card.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
        card.BorderSizePixel  = 0
        card.Text  = ""
        card.ZIndex = 3
        card.Parent = cardRow
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

        -- Accent bar at top
        local bar = Instance.new("Frame", card)
        bar.Size  = UDim2.new(1, 0, 0, 4)
        bar.BackgroundColor3 = info.Color
        bar.BorderSizePixel  = 0
        bar.ZIndex = 4
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 3)

        -- Discipline name
        _makeLabel(card, {
            Text      = string.upper(discId),
            Size      = UDim2.new(1, -16, 0, 32),
            Position  = UDim2.fromOffset(8, 16),
            Font      = Enum.Font.GothamBold,
            TextColor3 = info.Color,
            TextSize  = 18,
            ZIndex    = 4,
        })

        -- Tagline
        _makeLabel(card, {
            Text      = info.Tagline,
            Size      = UDim2.new(1, -16, 0, 20),
            Position  = UDim2.fromOffset(8, 50),
            Font      = Enum.Font.GothamMedium,
            TextColor3 = Color3.fromRGB(200, 195, 185),
            TextSize  = 13,
            TextWrapped = true,
            ZIndex    = 4,
        })

        -- Divider
        local div = Instance.new("Frame", card)
        div.Position = UDim2.fromOffset(8, 78)
        div.Size     = UDim2.new(1, -16, 0, 1)
        div.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        div.BorderSizePixel  = 0
        div.ZIndex = 4

        -- Stats line
        _makeLabel(card, {
            Text      = info.Stats,
            Size      = UDim2.new(1, -16, 0, 52),
            Position  = UDim2.fromOffset(8, 88),
            Font      = Enum.Font.Gotham,
            TextColor3 = Color3.fromRGB(150, 148, 140),
            TextSize  = 12,
            TextWrapped = true,
            ZIndex    = 4,
        })

        -- Key stats from DisciplineConfig
        local statsText = ""
        if cfg then
            statsText = ("[Posture %d  •  Breath %d]"):format(
                cfg.postureMax or 100,
                cfg.breathPool or 100
            )
        end
        _makeLabel(card, {
            Text      = statsText,
            Size      = UDim2.new(1, -16, 0, 22),
            Position  = UDim2.fromOffset(8, 144),
            Font      = Enum.Font.Code,
            TextColor3 = info.Color,
            TextSize  = 11,
            ZIndex    = 4,
        })

        -- Select button
        local selectBtn = Instance.new("TextButton", card)
        selectBtn.AnchorPoint = Vector2.new(0.5, 1)
        selectBtn.Position    = UDim2.new(0.5, 0, 1, -12)
        selectBtn.Size        = UDim2.new(1, -24, 0, 36)
        selectBtn.BackgroundColor3 = info.Color
        selectBtn.BorderSizePixel  = 0
        selectBtn.Text      = "SELECT"
        selectBtn.Font      = Enum.Font.GothamBold
        selectBtn.TextColor3 = Color3.fromRGB(10, 10, 16)
        selectBtn.TextSize  = 14
        selectBtn.ZIndex    = 5
        Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 4)

        -- Hover tint
        selectBtn.MouseEnter:Connect(function()
            TweenService:Create(selectBtn,
                TweenInfo.new(0.12),
                {BackgroundTransparency = 0.15}
            ):Play()
        end)
        selectBtn.MouseLeave:Connect(function()
            TweenService:Create(selectBtn,
                TweenInfo.new(0.12),
                {BackgroundTransparency = 0}
            ):Play()
        end)

        -- Capture local variable for closure
        local capturedId = discId
        selectBtn.Activated:Connect(function()
            -- Disable all buttons immediately to prevent double-fire
            for _, child in cardRow:GetChildren() do
                if child:IsA("TextButton") then child.Active = false end
                for _, grandchild in child:GetChildren() do
                    if grandchild:IsA("TextButton") then grandchild.Active = false end
                end
            end

            NetworkController:SendToServer("DisciplineSelected", {
                DisciplineId = capturedId,
            })

            -- Fade out then destroy (DisciplineConfirmed will also destroy)
            TweenService:Create(gui, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
            task.delay(0.5, _destroyDisciplineGui)
        end)
    end

    _disciplineGui = gui
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
        TotalResonance      = _state.TotalResonance,
        ResonanceShards     = _state.ResonanceShards,
        CurrentRing         = _state.CurrentRing,
        SoftCap             = _state.SoftCap,
        IsSoftCapped        = _state.IsSoftCapped,
        HasChosenDiscipline = _state.HasChosenDiscipline,
        DisciplineId        = _state.DisciplineId,
        OmenMarks           = _state.OmenMarks,
    }
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function ProgressionController:Init(dependencies)
    print("[ProgressionController] Initializing...")
    self._initialized = true
    print("[ProgressionController] Initialized")
end

function ProgressionController:Start()
    print("[ProgressionController] Starting...")

    -- Full state sync on join
    NetworkController:RegisterHandler("ProgressionSync", function(packet: any)
        _state.TotalResonance      = packet.TotalResonance or 0
        _state.ResonanceShards     = packet.ResonanceShards or 0
        _state.CurrentRing         = packet.CurrentRing or 1
        _state.SoftCap             = packet.SoftCap or 2000
        _state.HasChosenDiscipline = packet.HasChosenDiscipline or false
        _state.DisciplineId        = packet.DisciplineId or "Wayward"
        _state.OmenMarks           = packet.OmenMarks or 0
        _state.IsSoftCapped        = _state.SoftCap ~= -1
            and _state.TotalResonance >= _state.SoftCap

        print(("[ProgressionController] Sync received — Ring %d, %d Resonance, %d Shards")
            :format(_state.CurrentRing, _state.TotalResonance, _state.ResonanceShards))

        _notifyListeners()
    end)

    -- Incremental Resonance update
    NetworkController:RegisterHandler("ResonanceUpdate", function(packet: any)
        _state.TotalResonance  = packet.TotalResonance or _state.TotalResonance
        _state.ResonanceShards = packet.ResonanceShards or _state.ResonanceShards
        _state.CurrentRing     = packet.CurrentRing or _state.CurrentRing
        _state.SoftCap         = packet.SoftCap or _state.SoftCap
        _state.IsSoftCapped    = packet.IsSoftCapped == true

        local delta = packet.ShardDelta or 0
        local source = packet.Source or "unknown"

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

        _notifyListeners()
    end)

    -- Discipline selection required
    NetworkController:RegisterHandler("DisciplineSelectRequired", function(_packet: any)
        print("[ProgressionController] Discipline selection required — opening UI")
        task.spawn(_buildDisciplineGui)
    end)

    -- Discipline confirmed by server
    NetworkController:RegisterHandler("DisciplineConfirmed", function(packet: any)
        _state.HasChosenDiscipline = true
        _state.DisciplineId        = packet.DisciplineId or _state.DisciplineId

        print(("[ProgressionController] Discipline confirmed: %s"):format(_state.DisciplineId))

        _destroyDisciplineGui()
        _notifyListeners()
    end)

    print("[ProgressionController] Started")
end

return ProgressionController
