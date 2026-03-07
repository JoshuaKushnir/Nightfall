--!strict
--[[
    Class: CharacterCreationController
    Description: Handles the first-join Aspect selection screen. When the server
                 signals that the local player has no Aspect (CharacterCreationRequired),
                 this controller renders a 5-card picker UI. The player selects one,
                 the server validates and fires SelectAspectResult/AspectAssigned,
                 and the UI tears itself down.
    Dependencies: NetworkController, AspectRegistry
    Issue: #141 — Character creation: Aspect selection screen

    Usage:
        Auto-loaded by client runtime. Call order: after NetworkController.
        No public API — purely reactive (listen-only after Init).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)

local CharacterCreationController = {}

-- Private state
local _networkController: any = nil
local _pickerGui: ScreenGui? = nil
local _selectionLocked = false

-- Display order — Marrow excluded (IsLocked)
local SELECTABLE_ASPECTS: {string} = {"Ash", "Tide", "Ember", "Gale", "Void"}

-- ──────────────────────────────────────────────────────────────────────────────
-- Private helpers
-- ──────────────────────────────────────────────────────────────────────────────

local function _hidePicker()
    if _pickerGui then
        _pickerGui:Destroy()
        _pickerGui = nil
    end
    _selectionLocked = false
end

local function _onSelectClicked(aspectId: string, cardRow: Frame)
    if _selectionLocked then return end
    _selectionLocked = true

    -- Visually indicate selection pending
    for _, child in cardRow:GetChildren() do
        if child:IsA("Frame") then
            local btn = child:FindFirstChildWhichIsA("TextButton")
            if btn then
                btn.Active = false
                if child.Name == "Card_" .. aspectId then
                    btn.Text = "CHOOSING..."
                else
                    btn.BackgroundColor3 = Color3.fromRGB(60, 55, 65)
                    btn.TextColor3 = Color3.fromRGB(120, 110, 120)
                end
            end
        end
    end

    _networkController:SendToServer("SelectAspect", { AspectId = aspectId })
end

local function _showPicker()
    if _pickerGui then return end  -- already visible

    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    -- Root GUI
    local gui = Instance.new("ScreenGui")
    gui.Name = "CharacterCreationGui"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui
    _pickerGui = gui

    -- Dark overlay — blocks click-through, dims game world
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.30
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 1
    overlay.Parent = gui

    -- Main panel
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.new(0.88, 0, 0.78, 0)
    panel.Position = UDim2.fromScale(0.06, 0.11)
    panel.BackgroundColor3 = Color3.fromRGB(12, 9, 18)
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.ZIndex = 2
    panel.Parent = gui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 18)
    panelCorner.Parent = panel

    -- Header
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 56)
    title.Position = UDim2.fromOffset(0, 0)
    title.BackgroundTransparency = 1
    title.Text = "CHOOSE YOUR ASPECT"
    title.TextColor3 = Color3.fromRGB(235, 225, 210)
    title.TextSize = 32
    title.Font = Enum.Font.GothamBold
    title.ZIndex = 3
    title.Parent = panel

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.new(1, 0, 0, 26)
    subtitle.Position = UDim2.fromOffset(0, 56)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Your choice is permanent. Choose carefully."
    subtitle.TextColor3 = Color3.fromRGB(170, 155, 140)
    subtitle.TextSize = 16
    subtitle.Font = Enum.Font.Gotham
    subtitle.ZIndex = 3
    subtitle.Parent = panel

    -- Card row container
    local cardRow = Instance.new("Frame")
    cardRow.Name = "CardRow"
    cardRow.Size = UDim2.new(1, -48, 1, -108)
    cardRow.Position = UDim2.fromOffset(24, 96)
    cardRow.BackgroundTransparency = 1
    cardRow.ZIndex = 3
    cardRow.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 14)
    layout.Parent = cardRow

    -- Build one card per selectable Aspect
    for _, id in SELECTABLE_ASPECTS do
        local cfg = AspectRegistry.GetAspect(id :: any)
        if not cfg or cfg.IsLocked then continue end

        local base = cfg.ThemeColor
        local dark = Color3.fromRGB(
            math.clamp(math.floor(base.R * 255 * 0.28), 0, 255),
            math.clamp(math.floor(base.G * 255 * 0.28), 0, 255),
            math.clamp(math.floor(base.B * 255 * 0.28), 0, 255)
        )

        local card = Instance.new("Frame")
        card.Name = "Card_" .. id
        card.Size = UDim2.new(0.175, 0, 1, 0)
        card.BackgroundColor3 = dark
        card.BorderSizePixel = 0
        card.ZIndex = 4
        card.Parent = cardRow

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 12)
        cardCorner.Parent = card

        -- Accent stripe at top
        local accent = Instance.new("Frame")
        accent.Name = "Accent"
        accent.Size = UDim2.new(1, 0, 0, 5)
        accent.Position = UDim2.fromScale(0, 0)
        accent.BackgroundColor3 = base
        accent.BorderSizePixel = 0
        accent.ZIndex = 5
        accent.Parent = card

        local accentCorner = Instance.new("UICorner")
        accentCorner.CornerRadius = UDim.new(0, 12)
        accentCorner.Parent = accent

        -- Aspect name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "AspectName"
        nameLabel.Size = UDim2.new(1, -10, 0, 38)
        nameLabel.Position = UDim2.fromOffset(5, 18)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = cfg.DisplayName
        nameLabel.TextColor3 = base
        nameLabel.TextSize = 22
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.ZIndex = 5
        nameLabel.Parent = card

        -- Description
        local desc = Instance.new("TextLabel")
        desc.Name = "Description"
        desc.Size = UDim2.new(1, -12, 0, 90)
        desc.Position = UDim2.fromOffset(6, 60)
        desc.BackgroundTransparency = 1
        desc.Text = cfg.Description
        desc.TextColor3 = Color3.fromRGB(215, 205, 200)
        desc.TextSize = 13
        desc.Font = Enum.Font.Gotham
        desc.TextWrapped = true
        desc.ZIndex = 5
        desc.Parent = card

        -- Select button
        local btn = Instance.new("TextButton")
        btn.Name = "SelectBtn"
        btn.Size = UDim2.new(1, -16, 0, 38)
        btn.Position = UDim2.new(0, 8, 1, -50)
        btn.BackgroundColor3 = base
        btn.BorderSizePixel = 0
        btn.Text = "CHOOSE"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 15
        btn.Font = Enum.Font.GothamBold
        btn.ZIndex = 5
        btn.Parent = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn

        local capturedId = id
        btn.Activated:Connect(function()
            _onSelectClicked(capturedId, cardRow)
        end)
    end

    print("[CharacterCreationController] Aspect picker displayed")
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ──────────────────────────────────────────────────────────────────────────────

function CharacterCreationController:Init(dependencies: {[string]: any})
    _networkController = dependencies.NetworkController
    assert(_networkController, "[CharacterCreationController] Missing NetworkController dependency")

    -- Server → show the picker (player has no Aspect)
    _networkController:RegisterHandler("CharacterCreationRequired", function(_packet: any)
        task.defer(_showPicker)
    end)

    -- Server confirmed the selection → hide
    _networkController:RegisterHandler("SelectAspectResult", function(packet: any)
        if type(packet) == "table" and packet.Success == true then
            _hidePicker()
        elseif type(packet) == "table" and packet.Success == false then
            -- Allow reselection if the server rejects (e.g. race condition retry)
            _selectionLocked = false
            warn("[CharacterCreationController] Selection rejected: " .. tostring(packet.Reason))
        end
    end)

    -- AspectAssigned: also dismiss as a fallback (fired by AssignAspect)
    _networkController:RegisterHandler("AspectAssigned", function(_packet: any)
        if _pickerGui then
            _hidePicker()
        end
    end)
end

function CharacterCreationController:Start()
    print("[CharacterCreationController] Started")
end

return CharacterCreationController
