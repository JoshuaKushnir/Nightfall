-- ReplicatedStorage/Modules/UI/NotificationService.lua
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NotificationService = {}

function NotificationService.DisplayPlaque(title: string, subtitle: string)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:FindFirstChild("EtherealNotifications") or Instance.new("ScreenGui")
	screenGui.Name = "EtherealNotifications"
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- Create Plaque Container
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0.4, 0, 0.2, 0)
	frame.Position = UDim2.new(0.3, 0, 0.4, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0.6, 0)
	titleLabel.Text = title:upper()
	titleLabel.Font = Enum.Font.Antique
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	titleLabel.Parent = frame

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, 0, 0.3, 0)
	subLabel.Position = UDim2.new(0, 0, 0.6, 0)
	subLabel.Text = subtitle
	subLabel.Font = Enum.Font.Italic
	subLabel.TextColor3 = Color3.fromRGB(200, 230, 255)
	subLabel.TextScaled = true
	subLabel.BackgroundTransparency = 1
	subLabel.TextTransparency = 1
	subLabel.Parent = frame

	-- Animation Sequence
	task.spawn(function()
		local fadeIn = TweenInfo.new(2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(titleLabel, fadeIn, {TextTransparency = 0}):Play()
		task.wait(0.5)
		TweenService:Create(subLabel, fadeIn, {TextTransparency = 0.2}):Play()
		
		task.wait(4) -- Display time
		
		local fadeOut = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(titleLabel, fadeOut, {TextTransparency = 1}):Play()
		TweenService:Create(subLabel, fadeOut, {TextTransparency = 1}):Play()
	end)
end

return NotificationService