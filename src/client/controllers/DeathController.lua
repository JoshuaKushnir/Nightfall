--!strict
--[[
    Class: DeathController
    Description: Handles client-side death feedback beyond the death screen
                 (which is owned by CombatFeedbackUI). Specifically:
                   - Listens for ShardLost and shows a "Shards Lost" popup HUD message
                   - Listens for PlayerRespawned to dismiss any lingering death UI
    Dependencies: NetworkController
    Issue: #144 — Death respawn flow
]]

local Players = game:GetService("Players")

local DeathController = {}

-- Private state
local _networkController: any  = nil
local _shardPopup: ScreenGui?  = nil

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
    Auto-dismisses after 3.5 seconds.
]]
local function _showShardLostPopup(loss: number, newTotal: number)
    _dismissShardPopup()

    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "ShardLostGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui
    _shardPopup = gui

    -- Pill container
    local frame = Instance.new("Frame")
    frame.Name = "Pill"
    frame.Size = UDim2.new(0, 280, 0, 56)
    frame.Position = UDim2.new(0.5, -140, 0, 64)
    frame.BackgroundColor3 = Color3.fromRGB(24, 8, 8)
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
    icon.TextColor3 = Color3.fromRGB(200, 50, 50)
    icon.TextSize = 26
    icon.Font = Enum.Font.GothamBold
    icon.ZIndex = 11
    icon.Parent = frame

    -- Loss label
    local lossLabel = Instance.new("TextLabel")
    lossLabel.Name = "Loss"
    lossLabel.Size = UDim2.new(1, -52, 0.55, 0)
    lossLabel.Position = UDim2.fromOffset(48, 4)
    lossLabel.BackgroundTransparency = 1
    lossLabel.Text = "-" .. tostring(loss) .. " Shards"
    lossLabel.TextColor3 = Color3.fromRGB(220, 120, 120)
    lossLabel.TextSize = 17
    lossLabel.Font = Enum.Font.GothamBold
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
    remainLabel.TextColor3 = Color3.fromRGB(160, 140, 140)
    remainLabel.TextSize = 13
    remainLabel.Font = Enum.Font.Gotham
    remainLabel.TextXAlignment = Enum.TextXAlignment.Left
    remainLabel.ZIndex = 11
    remainLabel.Parent = frame

    -- Auto-dismiss after 3.5 s with fade
    task.delay(2.5, function()
        if not _shardPopup then return end
        -- Fade out over 0.6 s
        for i = 1, 12 do
            if not _shardPopup then return end
            frame.BackgroundTransparency = 0.15 + (i / 12) * 0.85
            icon.TextTransparency       = i / 12
            lossLabel.TextTransparency  = i / 12
            remainLabel.TextTransparency = i / 12
            task.wait(0.05)
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
