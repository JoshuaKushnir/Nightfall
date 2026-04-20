--!strict
--[[
	HUDPrimitives.lua

	Reusable HUD UI component builders.

	Provides factory functions for creating consistent HUD elements that use
	UITheme tokens and follow the high-ornate design language.

	Components:
	- PanelShell: dark themed frame with ornate border
	- StatBar: labeled progress bar with fill and threshold coloring
	- ValueChip: icon + label + value (e.g., "◈ Shards: 42")
	- Toast: notification card with fade-in/out
	- Overlay: full-screen semi-transparent overlay
	- Label: themed text label
]]

local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)

export type PanelShell = {
	Root: Frame,
	Content: Frame,
}

export type StatBar = {
	Root: Frame,
	Label: TextLabel,
	Fill: Frame,
	Value: TextLabel,
}

export type ValueChip = {
	Root: Frame,
	Label: TextLabel,
	Value: TextLabel,
}

export type Toast = {
	Root: ScreenGui,
	Container: Frame,
	Text: TextLabel,
	Dismiss: () -> (),
}

local HUDPrimitives = {}

--------------------------------------------------------------------------------
-- Helper: Apply corner radius
--------------------------------------------------------------------------------
function HUDPrimitives.applyCorner(instance: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = instance
	return corner
end

local function applyStroke(instance: Instance, color: Color3, thickness: number, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = instance
	return stroke
end

--------------------------------------------------------------------------------
-- PanelShell: Dark themed frame with border
--------------------------------------------------------------------------------
function HUDPrimitives.PanelShell(
	name: string,
	size: UDim2,
	position: UDim2?,
	noBorder: boolean?
): PanelShell
	local root = Instance.new("Frame")
	root.Name = name
	root.Size = size
	root.Position = position or UDim2.new(0, 0, 0, 0)
	root.BackgroundColor3 = UITheme.Palette.PanelDark
	root.BorderSizePixel = 0

	-- Ornate border
	if not noBorder then
		applyCorner(root, UITheme.Corners.Medium)
		applyStroke(root, UITheme.Palette.AccentIron, UITheme.Strokes.Ornate, 0.3)
	end

	-- Content container (fills panel with padding)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0

	-- Add padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UITheme.Spacing.PaddingMedium
	padding.PaddingRight = UITheme.Spacing.PaddingMedium
	padding.PaddingTop = UITheme.Spacing.PaddingSmall
	padding.PaddingBottom = UITheme.Spacing.PaddingSmall
	padding.Parent = content

	content.Parent = root

		return {
			Root = root,
			Content = content,
			PanelBackground = root,
		}
end

--------------------------------------------------------------------------------
-- Label: Themed text label
--------------------------------------------------------------------------------
function HUDPrimitives.Label(
	text: string,
	fontSize: number?,
	color: Color3?,
	bold: boolean?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Size = UDim2.new(1, 0, 0, fontSize or UITheme.Typography.SizeMedium)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0

	label.Font = if bold then UITheme.Typography.FontBold else UITheme.Typography.FontRegular
	label.TextSize = fontSize or UITheme.Typography.SizeMedium
	label.TextColor3 = color or UITheme.Palette.TextPrimary
	label.TextScaled = false
	label.TextWrapped = true

	return label
end

--------------------------------------------------------------------------------
-- StatBar: Labeled progress bar with fill and optional threshold coloring
--------------------------------------------------------------------------------
function HUDPrimitives.StatBar(
	name: string,
	label: string,
	width: number,
	height: number,
	initialValue: number?
): StatBar
	local value = initialValue or 0.5

	-- Root container
	local root = Instance.new("Frame")
	root.Name = name
	root.Size = UDim2.new(0, width, 0, height + 24) -- height for bar + label space
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- Label above bar
	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Text = label
	labelText.Size = UDim2.new(1, 0, 0, 16)
	labelText.BackgroundTransparency = 1
	labelText.BorderSizePixel = 0
	labelText.Font = UITheme.Typography.FontBold
	labelText.TextSize = UITheme.Typography.SizeSmall
	labelText.TextColor3 = UITheme.Palette.TextSecondary
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = root

	-- Bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, 0, 0, height)
	barBg.Position = UDim2.new(0, 0, 0, 18)
	barBg.BackgroundColor3 = UITheme.Palette.PanelMid
	barBg.BorderSizePixel = 0
	applyCorner(barBg, UITheme.Corners.Small)
	barBg.Parent = root

	-- Bar fill (clipped to barBg bounds via ClipsDescendants)
	barBg.ClipsDescendants = true
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(value, 0, 1, 0)
	fill.BackgroundColor3 = UITheme.Palette.HealthGreen
	fill.BorderSizePixel = 0
	applyCorner(fill, UITheme.Corners.Small)
	fill.Parent = barBg

	-- Value label (overlaid on bar)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Text = string.format("%.0f%%", value * 100)
	valueLabel.Size = UDim2.new(1, 0, 1, 0)
	valueLabel.Position = UDim2.new(0, 0, 0, 18)
	valueLabel.BackgroundTransparency = 1
	valueLabel.BorderSizePixel = 0
	valueLabel.Font = UITheme.Typography.FontBold
	valueLabel.TextSize = UITheme.Typography.SizeSmall
	valueLabel.TextColor3 = UITheme.Palette.TextPrimary
	valueLabel.TextXAlignment = Enum.TextXAlignment.Center
	valueLabel.TextYAlignment = Enum.TextYAlignment.Center
	valueLabel.ZIndex = barBg.ZIndex + 1
	valueLabel.Parent = root

	return {
		Root = root,
		Label = labelText,
		Fill = fill,
		Value = valueLabel,
	}
end

--------------------------------------------------------------------------------
-- ValueChip: Icon + label + value display (compact)
--------------------------------------------------------------------------------
function HUDPrimitives.ValueChip(
	name: string,
	labelText: string,
	valueText: string,
	icon: string?
): ValueChip
	-- Root chip
	local root = Instance.new("Frame")
	root.Name = name
	root.Size = UDim2.new(0, 120, 0, 24)
	root.BackgroundColor3 = UITheme.Palette.PanelMid
	root.BorderSizePixel = 0
	applyCorner(root, UITheme.Corners.Medium)

	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UITheme.Spacing.PaddingSmall
	padding.PaddingRight = UITheme.Spacing.PaddingSmall
	padding.Parent = root

	-- List layout (horizontal)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UITheme.Spacing.GapSmall
	layout.Parent = root

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Text = labelText
	label.Size = UDim2.new(1, -40, 1, 0) -- Flexible width minus value
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = UITheme.Typography.FontRegular
	label.TextSize = UITheme.Typography.SizeSmall
	label.TextColor3 = UITheme.Palette.TextSecondary
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = root

	-- Value
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Text = valueText
	value.Size = UDim2.new(0, 40, 1, 0)
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.Font = UITheme.Typography.FontBold
	value.TextSize = UITheme.Typography.SizeSmall
	value.TextColor3 = UITheme.Palette.TextAccent
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = root

	return {
		Root = root,
		Label = label,
		Value = value,
	}
end

--------------------------------------------------------------------------------
-- Toast: Notification card with fade-in/out
--------------------------------------------------------------------------------
function HUDPrimitives.Toast(
	message: string,
	duration: number?
): Toast
	local displayDuration = duration or 3.0

	-- ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Toast"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 50

	-- Container frame
	local container = Instance.new("Frame")
	container.Name = "ToastContainer"
	container.Size = UDim2.new(0, 280, 0, 60)
	container.Position = UDim2.new(0.5, -140, 1, -100) -- Bottom center
	container.BackgroundColor3 = UITheme.Palette.PanelMid
	container.BorderSizePixel = 0
	applyCorner(container, UITheme.Corners.Medium)
	applyStroke(container, UITheme.Palette.AccentIron, UITheme.Strokes.Thin, 0.4)
	container.Parent = screenGui

	-- Text
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Text = message
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.BorderSizePixel = 0
	text.Font = UITheme.Typography.FontRegular
	text.TextSize = UITheme.Typography.SizeSmall
	text.TextColor3 = UITheme.Palette.TextPrimary
	text.TextWrapped = true
	text.Parent = container

	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UITheme.Spacing.PaddingSmall
	padding.PaddingRight = UITheme.Spacing.PaddingSmall
	padding.Parent = container

	-- Fade in immediately (non-blocking)
	TweenService:Create(
		container,
		TweenInfo.new(UITheme.Motion.DurationQuick, UITheme.Motion.EasingQuick, UITheme.Motion.EasingInOut),
		{ BackgroundTransparency = 0 }
	):Play()

	-- Dismiss function
	local function dismiss()
		local fadeOut = TweenService:Create(
			container,
			TweenInfo.new(UITheme.Motion.DurationQuick, UITheme.Motion.EasingQuick, UITheme.Motion.EasingInOut),
			{ BackgroundTransparency = 1 }
		)
		fadeOut.Completed:Connect(function()
			screenGui:Destroy()
		end)
		fadeOut:Play()
	end

	-- Auto-dismiss after duration (non-blocking — spawned so constructor returns immediately)
	task.delay(displayDuration, dismiss)

	return {
		Root = screenGui,
		Container = container,
		Text = text,
		Dismiss = dismiss,
	}
end

--------------------------------------------------------------------------------
-- Overlay: Full-screen semi-transparent overlay
--------------------------------------------------------------------------------
function HUDPrimitives.Overlay(
	name: string,
	color: Color3?,
	transparency: number?
): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = name
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = true

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = color or Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = transparency or 0.5
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	return screenGui
end

return HUDPrimitives
