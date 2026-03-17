--!strict
--[[
	HUDLayout.lua
	
	Centralized HUD positioning, anchoring, and safe-area aware placement.
	
	All HUD elements reference positions from this module. Makes layout changes
	easy: update once, applies everywhere.
	
	Layout strategy:
	- Anchor points define reference locations on screen
	- Offsets position elements relative to anchors
	- Safe areas account for mobile/notch considerations
	- Layer order prevents overlap
]]

export type HUDLayout = {
	Anchors: {
		TopLeft: Vector2,
		TopCenter: Vector2,
		TopRight: Vector2,
		CenterLeft: Vector2,
		Center: Vector2,
		CenterRight: Vector2,
		BottomLeft: Vector2,
		BottomCenter: Vector2,
		BottomRight: Vector2,
	},
	
	SafeArea: {
		Margin: number,
		TopMargin: number,
		BottomMargin: number,
		SideMargin: number,
	},
	
	Layers: {
		Background: number,
		HUD: number,
		Modal: number,
		Toast: number,
		Debug: number,
	},
}

local HUDLayout: HUDLayout = {
	-- Anchor points: position UDim2s for common screen locations
	Anchors = {
		TopLeft = Vector2.new(0, 0),
		TopCenter = Vector2.new(0.5, 0),
		TopRight = Vector2.new(1, 0),
		CenterLeft = Vector2.new(0, 0.5),
		Center = Vector2.new(0.5, 0.5),
		CenterRight = Vector2.new(1, 0.5),
		BottomLeft = Vector2.new(0, 1),
		BottomCenter = Vector2.new(0.5, 1),
		BottomRight = Vector2.new(1, 1),
	},
	
	-- Safe area margins (pixels inset from edges)
	SafeArea = {
		Margin = 16,          -- Generic edge distance
		TopMargin = 12,       -- Below status bar
		BottomMargin = 16,    -- Above taskbar/safe zone
		SideMargin = 12,      -- From left/right edges
	},
	
	-- Layer ordering (DisplayOrder values)
	Layers = {
		Background = 0,
		HUD = 20,
		Modal = 50,
		Toast = 60,
		Debug = 100,
	},
}

--------------------------------------------------------------------------------
-- Position helpers: Return UDim2 for common placements
--------------------------------------------------------------------------------

function HUDLayout.PositionTopLeft(offsetX: number, offsetY: number): UDim2
	return UDim2.new(0, HUDLayout.SafeArea.SideMargin + offsetX, 0, HUDLayout.SafeArea.TopMargin + offsetY)
end

function HUDLayout.PositionTopCenter(offsetX: number, offsetY: number, width: number): UDim2
	return UDim2.new(0.5, -width / 2 + offsetX, 0, HUDLayout.SafeArea.TopMargin + offsetY)
end

function HUDLayout.PositionTopRight(offsetX: number, offsetY: number, width: number): UDim2
	return UDim2.new(1, -HUDLayout.SafeArea.SideMargin - width + offsetX, 0, HUDLayout.SafeArea.TopMargin + offsetY)
end

function HUDLayout.PositionCenterLeft(offsetX: number, offsetY: number, height: number): UDim2
	return UDim2.new(0, HUDLayout.SafeArea.SideMargin + offsetX, 0.5, -height / 2 + offsetY)
end

function HUDLayout.PositionCenter(offsetX: number, offsetY: number, width: number, height: number): UDim2
	return UDim2.new(0.5, -width / 2 + offsetX, 0.5, -height / 2 + offsetY)
end

function HUDLayout.PositionCenterRight(offsetX: number, offsetY: number, width: number, height: number): UDim2
	return UDim2.new(1, -HUDLayout.SafeArea.SideMargin - width + offsetX, 0.5, -height / 2 + offsetY)
end

function HUDLayout.PositionBottomLeft(offsetX: number, offsetY: number, height: number): UDim2
	return UDim2.new(0, HUDLayout.SafeArea.SideMargin + offsetX, 1, -HUDLayout.SafeArea.BottomMargin - height + offsetY)
end

function HUDLayout.PositionBottomCenter(offsetX: number, offsetY: number, width: number, height: number): UDim2
	return UDim2.new(0.5, -width / 2 + offsetX, 1, -HUDLayout.SafeArea.BottomMargin - height + offsetY)
end

function HUDLayout.PositionBottomRight(offsetX: number, offsetY: number, width: number, height: number): UDim2
	return UDim2.new(1, -HUDLayout.SafeArea.SideMargin - width + offsetX, 1, -HUDLayout.SafeArea.BottomMargin - height + offsetY)
end

--------------------------------------------------------------------------------
-- Layout presets for specific HUD sections
--------------------------------------------------------------------------------

-- Core HUD position: top-left, below zone notif
function HUDLayout.CoreHUDPosition(): UDim2
	return HUDLayout.PositionTopLeft(0, 60)
end

-- Movement HUD position: bottom-left
function HUDLayout.MovementHUDPosition(): UDim2
	return HUDLayout.PositionBottomLeft(0, 0, 100)
end

-- Resonance display: top-right
function HUDLayout.ResonanceHUDPosition(width: number, height: number): UDim2
	return HUDLayout.PositionTopRight(0, 12, width)
end

-- Posture bar: bottom-center, above movement HUD
function HUDLayout.PostureBarPosition(width: number, height: number): UDim2
	return HUDLayout.PositionBottomCenter(0, -110, width, height)
end

-- Witness progress bar: mid-right side
function HUDLayout.WitnessBarPosition(width: number, height: number): UDim2
	return UDim2.new(0.85, -width / 2, 0.35, -height / 2)
end

-- Shard loss popup: top-center
function HUDLayout.ShardLostPopupPosition(width: number, height: number): UDim2
	return HUDLayout.PositionTopCenter(0, 80, width)
end

-- Zone notification: top-center
function HUDLayout.ZoneNotificationPosition(width: number, height: number): UDim2
	return HUDLayout.PositionTopCenter(0, 20, width)
end

-- Floating damage numbers: world-relative, converted via Camera:WorldToScreenPoint
-- (No fixed UDim2 because position changes per-target)

-- Death overlay: full-screen, centered
function HUDLayout.DeathOverlayPosition(): UDim2
	return UDim2.new(0, 0, 0, 0)
end

-- Death screen text: center of screen
function HUDLayout.DeathScreenTextPosition(width: number, height: number): UDim2
	return HUDLayout.PositionCenter(0, -50, width, height)
end

return HUDLayout
