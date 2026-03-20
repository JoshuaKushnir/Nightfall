--!strict
--[[
	Class: WitnessController
	Description: Client-side controller for handling the Witnessing progression mechanic.
	Listens to server events (WitnessStarted, WitnessProgress, CodexUnlocked) and displays
	the observation progress bar and unlock toasts.
	Dependencies: NetworkController

	Usage:
		local WitnessController = require(path.to.WitnessController)
		WitnessController:Init(dependencies)
		WitnessController:Start()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkTypes = require(Shared.types.NetworkTypes)
local UITheme = require(script.Parent.Parent.modules.UITheme)
local HUDLayout = require(script.Parent.Parent.modules.HUDLayout)

local WitnessController = {}
WitnessController._initialized = false

local NetworkController = nil
local PlayerHUDController = nil

-- UI Elements
local witnessGui: ScreenGui
local witnessContainer: Frame
local witnessBar: Frame
local witnessLabel: TextLabel
local fadeTween: TweenBase?

-- Constants
local TOAST_DURATION = 4.0

--[[
	Creates the visual elements for the Witness progress bar and Toasts.
]]
local function createUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	witnessGui = Instance.new("ScreenGui")
	witnessGui.Name = "WitnessHUD"
	witnessGui.ResetOnSpawn = false
	witnessGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	witnessGui.DisplayOrder = HUDLayout.Layers.HUD
	witnessGui.Parent = playerGui

	-- Witness Progress Bar (Bottom Center)
	witnessContainer = Instance.new("Frame")
	witnessContainer.Name = "WitnessContainer"
	witnessContainer.Size = UDim2.new(0, 300, 0, 40)
	witnessContainer.Position = UDim2.new(0.5, -150, 0.8, 0)
	witnessContainer.BackgroundColor3 = UITheme.Palette.PanelDark
	witnessContainer.BackgroundTransparency = 1
	witnessContainer.BorderSizePixel = 0
	witnessContainer.Visible = false
	witnessContainer.Parent = witnessGui

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Palette.BreathTeal
	stroke.Thickness = UITheme.Strokes.Thin
	stroke.Parent = witnessContainer

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, -6, 1, -24)
	barBg.Position = UDim2.new(0, 3, 1, -19)
	barBg.BackgroundColor3 = UITheme.Palette.PanelMid
	barBg.BorderSizePixel = 0
	barBg.Parent = witnessContainer

	witnessBar = Instance.new("Frame")
	witnessBar.Name = "Fill"
	witnessBar.Size = UDim2.new(0, 0, 1, 0)
	witnessBar.BackgroundColor3 = UITheme.Palette.BreathTeal
	witnessBar.BorderSizePixel = 0
	witnessBar.Parent = barBg

	witnessLabel = Instance.new("TextLabel")
	witnessLabel.Name = "TargetLabel"
	witnessLabel.Size = UDim2.new(1, 0, 0, 16)
	witnessLabel.Position = UDim2.new(0, 0, 0, 2)
	witnessLabel.BackgroundTransparency = 1
	witnessLabel.Font = UITheme.Typography.FontBold
	witnessLabel.TextColor3 = UITheme.Palette.TextPrimary
	witnessLabel.TextSize = UITheme.Typography.SizeSmall
	witnessLabel.Text = "Witnessing..."
	witnessLabel.Parent = witnessContainer
end

function WitnessController:Init(dependencies: any)
	NetworkController = dependencies.NetworkController
	PlayerHUDController = dependencies.PlayerHUDController
	self._initialized = true

	createUI()
end

function WitnessController:Start()
	assert(self._initialized, "Must call Init() before Start()")

	NetworkController:RegisterHandler("WitnessStarted", function(packet: NetworkTypes.WitnessStartedPacket)
		witnessContainer.Visible = true
		witnessLabel.Text = "Witnessing: " .. (packet.TargetName or "Unknown")
		witnessBar.Size = UDim2.new(0, 0, 1, 0)

		if fadeTween then
			fadeTween:Cancel()
		end
		witnessContainer.BackgroundTransparency = 0
		witnessContainer:FindFirstChildOfClass("UIStroke").Transparency = 0
	end)

	NetworkController:RegisterHandler("WitnessProgress", function(packet: NetworkTypes.WitnessProgressPacket)
		if not witnessContainer.Visible then
			witnessContainer.Visible = true
			witnessContainer.BackgroundTransparency = 0
			witnessContainer:FindFirstChildOfClass("UIStroke").Transparency = 0
		end

		witnessLabel.Text = "Witnessing: " .. (packet.TargetName or "Unknown")

		local percent = math.clamp(packet.Progress, 0, 1)

		TweenService:Create(witnessBar, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
			Size = UDim2.new(percent, 0, 1, 0)
		}):Play()

		-- Hide if broken or completed
		if packet.Broken or percent >= 1 then
			task.delay(0.5, function()
				fadeTween = TweenService:Create(witnessContainer, TweenInfo.new(0.5), {BackgroundTransparency = 1})
				local strokeTween = TweenService:Create(witnessContainer:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.5), {Transparency = 1})

				fadeTween.Completed:Connect(function()
					witnessContainer.Visible = false
				end)

				fadeTween:Play()
				strokeTween:Play()
			end)
		end
	end)

	NetworkController:RegisterHandler("WitnessFailed", function(packet: NetworkTypes.WitnessFailedPacket)
		if witnessContainer.Visible then
			task.delay(0.5, function()
				fadeTween = TweenService:Create(witnessContainer, TweenInfo.new(0.5), {BackgroundTransparency = 1})
				local strokeTween = TweenService:Create(witnessContainer:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.5), {Transparency = 1})

				fadeTween.Completed:Connect(function()
					witnessContainer.Visible = false
				end)

				fadeTween:Play()
				strokeTween:Play()
			end)
		end
	end)

	NetworkController:RegisterHandler("CodexUnlocked", function(packet: NetworkTypes.CodexUnlockedPacket)
		if PlayerHUDController then
			PlayerHUDController:ShowToast(
				"Codex Unlocked",
				"Knowledge acquired: " .. packet.EntryId,
				UITheme.Palette.BreathTeal,
				5.0
			)
		end
	end)
end

return WitnessController
