--!strict
--[[
	UITheme.lua
	
	Centralized HUD visual tokens and design system.
	
	All HUD controllers reference this module instead of hardcoding colors, spacing, 
	typography, and animation timings. Makes HUD visual updates easy: edit once, apply everywhere.
	
	Design direction: High-ornate immersive (parchment + iron + gold accents)
	
	Categories:
	- Palette: base colors for dark theme
	- Typography: fonts, sizes, luminance
	- Spacing: padding, margins, gaps (scale)
	- Corners: standard border radius values
	- Strokes: border styling presets
	- Motion: animation timings and easing
	- BarThresholds: state-driven color transitions for bars
]]

export type UITheme = {
	Palette: {
		-- Panel backgrounds (high-ornate dark fantasy)
		PanelDark: Color3,
		PanelMid: Color3,
		PanelLight: Color3,
		
		-- Text (parchment tones)
		TextPrimary: Color3,
		TextSecondary: Color3,
		TextAccent: Color3,
		TextError: Color3,
		
		-- Interactive elements
		AccentGold: Color3,
		AccentIron: Color3,
		AccentBronze: Color3,
		
		-- State-specific
		HealthGreen: Color3,
		HealthYellow: Color3,
		HealthRed: Color3,
		
		BreathTeal: Color3,
		BreathYellow: Color3,
		BreathRed: Color3,
		
		PostureGrey: Color3,
		PostureOrange: Color3,
		PostureRed: Color3,
		
		MomentumGold: Color3,
		MomentumOrange: Color3,
		MomentumBright: Color3,
		
		-- Rarity colors
		RarityCommon: Color3,
		RarityUncommon: Color3,
		RarityRare: Color3,
		RarityEpic: Color3,
	},
	
	Typography: {
		-- Font family
		FontBold: Enum.Font,
		FontRegular: Enum.Font,
		
		-- Sizes (points)
		SizeLarge: number,
		SizeMedium: number,
		SizeSmall: number,
		SizeXSmall: number,
		
		-- Line height scale
		LineHeightLarge: number,
		LineHeightMedium: number,
		LineHeightSmall: number,
	},
	
	Spacing: {
		-- Base unit (multiples of 2px)
		Unit: number,
		PaddingLarge: UDim,
		PaddingMedium: UDim,
		PaddingSmall: UDim,
		PaddingXSmall: UDim,
		
		GapLarge: UDim,
		GapMedium: UDim,
		GapSmall: UDim,
	},
	
	Corners: {
		Large: UDim,
		Medium: UDim,
		Small: UDim,
	},
	
	Strokes: {
		Ornate: number,
		Medium: number,
		Thin: number,
	},
	
	Motion: {
		DurationQuick: number,
		DurationSmooth: number,
		DurationSlow: number,
		
		EasingQuick: Enum.EasingStyle,
		EasingSmooth: Enum.EasingStyle,
		EasingInOut: Enum.EasingDirection,
	},
	
	BarThresholds: {
		-- Health bar thresholds (green → yellow → red)
		HealthSafeThreshold: number, -- >= this is green
		HealthWarningThreshold: number, -- >= this is yellow
		HealthDangerThreshold: number, -- < this is red
		
		-- Posture bar thresholds (grey → orange → red)
		PostureSafeThreshold: number, -- < this is grey
		PostureWarningThreshold: number, -- < this is orange
		PostureDangerThreshold: number, -- >= this is red
		
		-- Breath bar thresholds (teal → yellow → red on exhaust)
		BreathSafeThreshold: number, -- > this is teal
		BreathWarningThreshold: number, -- > this is yellow
		
		-- Momentum color transitions
		MomentumLowThreshold: number, -- < this is dull gold
		MomentumHighThreshold: number, -- >= this is blazing gold
	},
}

local UITheme: UITheme = {
	Palette = {
		-- Panel backgrounds
		PanelDark = Color3.fromRGB(17, 14, 11),        -- Deep charcoal
		PanelMid = Color3.fromRGB(26, 21, 16),         -- Medium charcoal
		PanelLight = Color3.fromRGB(34, 28, 20),       -- Light charcoal
		
		-- Text (parchment tones)
		TextPrimary = Color3.fromRGB(222, 208, 182),   -- Parchment cream
		TextSecondary = Color3.fromRGB(138, 120, 96),  -- Muted bronze
		TextAccent = Color3.fromRGB(200, 164, 88),     -- Gold accent
		TextError = Color3.fromRGB(220, 80, 80),       -- Faded red
		
		-- Interactive elements
		AccentGold = Color3.fromRGB(200, 164, 88),     -- Warm gold
		AccentIron = Color3.fromRGB(110, 88, 56),      -- Dark iron
		AccentBronze = Color3.fromRGB(150, 110, 70),   -- Warm bronze
		
		-- Health bar states
		HealthGreen = Color3.fromRGB(80, 200, 80),     -- Vibrant green
		HealthYellow = Color3.fromRGB(255, 200, 50),   -- Warm yellow
		HealthRed = Color3.fromRGB(220, 60, 60),       -- Warning red
		
		-- Breath bar states
		BreathTeal = Color3.fromRGB(56, 182, 190),     -- Calm teal
		BreathYellow = Color3.fromRGB(255, 200, 50),   -- Warm yellow
		BreathRed = Color3.fromRGB(210, 60, 40),       -- Hot red
		
		-- Posture bar states (pressure gauge)
		PostureGrey = Color3.fromRGB(180, 180, 220),   -- Cool grey (safe)
		PostureOrange = Color3.fromRGB(255, 140, 50),  -- Warning orange
		PostureRed = Color3.fromRGB(220, 50, 50),      -- Danger red
		
		-- Momentum meter states
		MomentumGold = Color3.fromRGB(200, 164, 88),   -- Dull gold
		MomentumOrange = Color3.fromRGB(255, 140, 50), -- Medium gold
		MomentumBright = Color3.fromRGB(255, 200, 50), -- Blazing gold
		
		-- Rarity
		RarityCommon = Color3.fromRGB(200, 200, 200),  -- Grey
		RarityUncommon = Color3.fromRGB(100, 200, 100),-- Green
		RarityRare = Color3.fromRGB(100, 150, 255),    -- Blue
		RarityEpic = Color3.fromRGB(200, 100, 255),    -- Purple
	},
	
	Typography = {
		FontBold = Enum.Font.GothamBold,
		FontRegular = Enum.Font.Gotham,
		
		SizeLarge = 18,
		SizeMedium = 14,
		SizeSmall = 12,
		SizeXSmall = 10,
		
		LineHeightLarge = 1.4,
		LineHeightMedium = 1.3,
		LineHeightSmall = 1.2,
	},
	
	Spacing = {
		Unit = 2,
		PaddingLarge = UDim.new(0, 16),
		PaddingMedium = UDim.new(0, 12),
		PaddingSmall = UDim.new(0, 8),
		PaddingXSmall = UDim.new(0, 4),
		
		GapLarge = UDim.new(0, 16),
		GapMedium = UDim.new(0, 12),
		GapSmall = UDim.new(0, 6),
	},
	
	Corners = {
		Large = UDim.new(0, 12),
		Medium = UDim.new(0, 8),
		Small = UDim.new(0, 4),
	},
	
	Strokes = {
		Ornate = 2,
		Medium = 1.5,
		Thin = 1,
	},
	
	Motion = {
		DurationQuick = 0.2,
		DurationSmooth = 0.35,
		DurationSlow = 0.5,
		
		EasingQuick = Enum.EasingStyle.Quad,
		EasingSmooth = Enum.EasingStyle.Quad,
		EasingInOut = Enum.EasingDirection.Out,
	},
	
	BarThresholds = {
		-- Health: green until 50%, yellow until 20%, then red
		HealthSafeThreshold = 0.5,
		HealthWarningThreshold = 0.2,
		HealthDangerThreshold = 0,
		
		-- Posture: grey until 50%, orange until 80%, red at 80%+
		PostureSafeThreshold = 0.5,
		PostureWarningThreshold = 0.8,
		PostureDangerThreshold = 0.8,
		
		-- Breath: teal until 50%, yellow until 20%, red when exhausted
		BreathSafeThreshold = 0.5,
		BreathWarningThreshold = 0.2,
		
		-- Momentum: dull gold <50% multiplier, orange <85%, blazing >=85%
		MomentumLowThreshold = 0.5,
		MomentumHighThreshold = 0.85,
	},
}

return UITheme
