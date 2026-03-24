--!strict
--[[
    Class: DeathController
    Description: Handles client-side death feedback beyond the death screen
                 (which is owned by CombatFeedbackUI). Specifically:
                   - Listens for ShardLost and shows a "Shards Lost" popup HUD message
                   - Listens for PlayerRespawned to dismiss any lingering death UI
    Dependencies: NetworkController, UITheme, HUDLayout
    Issue: #144 — Death respawn flow
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(script.Parent.Parent.Parent.modules.UITheme)
local HUDLayout = require(script.Parent.Parent.Parent.modules.HUDLayout)

local DeathController = {}

-- Private state
local _networkController: any  = nil
local _shardPopup: ScreenGui?  = nil

-- UI timing constants
local SHARD_POPUP_HOLD_TIME = 2.5  -- Hold visible before fade
local SHARD_POPUP_FADE_TIME = 0.6  -- Fade out duration (12 steps × 0.05s)
local FADE_STEP_DURATION = 0.05

-- ─── UI helpers ───────────────────────────────────────────────────────────────

local function _dismissShardPopup()
    if _shardPopup then
        _shardPopup:Destroy()
        _shardPopup = nil
    end
end

--[[
    _showShardLostPopup(loss, newTotal)
    Displays a brief overlay in the top-centre showing how many Shards were lost.
    Auto-dismisses after 3.15 seconds (2.5s hold + 0.6s fade).
]]
local function _showShardLostPopup(loss: number, newTotal: number)
    _dismissShardPopup()

    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "ShardLostGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = HUDLayout.Layers.Toast
    gui.Parent = playerGui
    _shardPopup = gui

    -- Pill container
    local frame = Instance.new("Frame")
    frame.Name = "Pill"
    frame.Size = UDim2.new(0, 280, 0, 56)
    frame.Position = UDim2.new(0.5, -140, 0, 64)
    frame.BackgroundColor3 = UITheme.Palette.PanelDark
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.ZIndex = 10
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 28)
    corner.Parent = frame

    -- Shard icon (text symbol)
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 44, 1, 0)
    icon.Position = UDim2.fromOffset(6, 0)
    icon.BackgroundTransparency = 1
    icon.Text = "◈"
    icon.TextColor3 = UITheme.Palette.HealthRed
    icon.TextSize = 26
    icon.Font = UITheme.Typography.FontBold
    icon.ZIndex = 11
    icon.Parent = frame

    -- Loss label
    local lossLabel = Instance.new("TextLabel")
    lossLabel.Name = "Loss"
    lossLabel.Size = UDim2.new(1, -52, 0.55, 0)
    lossLabel.Position = UDim2.fromOffset(48, 4)
    lossLabel.BackgroundTransparency = 1
    lossLabel.Text = "-" .. tostring(loss) .. " Shards"
    lossLabel.TextColor3 = UITheme.Palette.HealthRed
    lossLabel.TextSize = UITheme.Typography.SizeMedium
    lossLabel.Font = UITheme.Typography.FontBold
    lossLabel.TextXAlignment = Enum.TextXAlignment.Left
    lossLabel.ZIndex = 11
    lossLabel.Parent = frame

    -- Remaining shards sub-text
    local remainLabel = Instance.new("TextLabel")
    remainLabel.Name = "Remaining"
    remainLabel.Size = UDim2.new(1, -52, 0.45, 0)
    remainLabel.Position = UDim2.new(0, 48, 0.55, 0)
    remainLabel.BackgroundTransparency = 1
    remainLabel.Text = tostring(newTotal) .. " remaining"
    remainLabel.TextColor3 = UITheme.Palette.TextSecondary
    remainLabel.TextSize = UITheme.Typography.SizeXSmall
    remainLabel.Font = UITheme.Typography.FontRegular
    remainLabel.TextXAlignment = Enum.TextXAlignment.Left
    remainLabel.ZIndex = 11
    remainLabel.Parent = frame

    -- Auto-dismiss after hold time with fade
    task.delay(SHARD_POPUP_HOLD_TIME, function()
        if not _shardPopup then return end
        -- Fade out over duration
        for i = 1, 12 do
            if not _shardPopup then return end
            frame.BackgroundTransparency = 0.15 + (i / 12) * 0.85
            icon.TextTransparency       = i / 12
            lossLabel.TextTransparency  = i / 12
            remainLabel.TextTransparency = i / 12
            task.wait(FADE_STEP_DURATION)
        end
        _dismissShardPopup()
    end)
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function DeathController:Init(dependencies: {[string]: any})
    _networkController = dependencies.NetworkController
    assert(_networkController, "[DeathController] Missing NetworkController dependency")

    -- Server fires this after ProgressionService.OnPlayerDied deducts shards
    _networkController:RegisterHandler("ShardLost", function(packet: any)
        if type(packet) ~= "table" then return end
        local loss     = tonumber(packet.Loss)     or 0
        local newTotal = tonumber(packet.NewTotal) or 0
        if loss > 0 then
            _showShardLostPopup(loss, newTotal)
        end
    end)

    -- Dismiss any lingering popups when the respawn completes
    _networkController:RegisterHandler("PlayerRespawned", function(_packet: any)
        _dismissShardPopup()
    end)
end

function DeathController:Start()
    print("[DeathController] Started")
end

return DeathController
