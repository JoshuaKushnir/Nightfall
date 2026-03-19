--!strict
--[[
    HUDTheme.lua  (Shared)

    Geometry and colour tokens for the bottom-centre HUD cluster.
    Kept separate from UITheme so cluster sizing can be tweaked
    independently of the broad design system.
]]

local AspectTypes = require(game:GetService("ReplicatedStorage").Shared.types.AspectTypes)

export type HUDTheme = {
    -- Distance from bottom edge to the bottom of the cluster (px)
    HUD_BOTTOM_OFFSET: number,

    -- Overall cluster width (px) — all bars reference this
    ClusterWidth: number,

    -- Health bar
    HealthBarWidth: number,   -- matches ClusterWidth for full-bleed look
    HealthBarHeight: number,
    HealthWarnThreshold: number,  -- below this → warm yellow
    HealthCritThreshold: number,  -- below this → red + pulse
    HealthFullColor: Color3,
    HealthWarnColor: Color3,
    HealthCritColor: Color3,

    -- Aspect-tinted UIStroke colour on the health bar
    AspectBorderColor: {[AspectTypes.AspectId]: Color3},

    -- Posture bar
    PostureBarHeight: number,
    PostureWarnThreshold: number,
    PostureWarnColor: Color3,

    -- Ambient bars (mana, breath) — width is ClusterWidth * scale
    AmbientBarHeight: number,
    ManaBarWidthScale: number,
    BreathBarWidthScale: number,

    -- Status icon row
    StatusIconSize: number,
    StatusIconSpacing: number,
    StatusIconCount: number,

    -- Ability slot row (mantras / active abilities)
    AbilitySlotSize: number,
    AbilitySlotCount: number,
    AbilitySlotSpacing: number,
}

local HUDTheme: HUDTheme = {
    HUD_BOTTOM_OFFSET = 90,

    ClusterWidth  = 340,
    HealthBarWidth  = 340,   -- full-bleed (same as ClusterWidth)
    HealthBarHeight = 22,
    HealthWarnThreshold = 0.40,
    HealthCritThreshold = 0.15,
    HealthFullColor = Color3.fromRGB(212, 164,  80), -- warm gold
    HealthWarnColor = Color3.fromRGB(255, 190,  80), -- amber
    HealthCritColor = Color3.fromRGB(205,  80,  60), -- blood red

    AspectBorderColor = {
        Ash    = Color3.fromRGB(160, 100,  40),
        Tide   = Color3.fromRGB( 45, 135, 190),
        Ember  = Color3.fromRGB(220,  80,  40),
        Gale   = Color3.fromRGB(190, 190,  90),
        Void   = Color3.fromRGB(120,  50, 170),
        Marrow = Color3.fromRGB(145,  55,  55),
    },

    PostureBarHeight     = 6,
    PostureWarnThreshold = 0.70,
    PostureWarnColor     = Color3.fromRGB(180, 80, 60),

    AmbientBarHeight     = 6,
    ManaBarWidthScale    = 0.70,   -- 238 px at ClusterWidth=340
    BreathBarWidthScale  = 0.55,   -- 187 px at ClusterWidth=340

    StatusIconSize    = 18,
    StatusIconSpacing =  6,
    StatusIconCount   =  8,

    AbilitySlotSize    = 32,
    AbilitySlotCount   =  4,
    AbilitySlotSpacing =  6,
}

return HUDTheme
