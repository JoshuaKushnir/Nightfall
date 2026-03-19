--!strict
--[[
    HUDTheme.lua  (Shared)

    Visual tokens for the 4-bar HUD cluster.
    HP · Posture · Mana · Luminance
]]

local AspectTypes = require(game:GetService("ReplicatedStorage").Shared.types.AspectTypes)

export type HUDTheme = {
    HUD_BOTTOM_OFFSET:  number,
    BarWidth:           number,
    HealthBarHeight:    number,
    AmbientBarHeight:   number,
    BarGap:             number,

    HealthWarnThreshold: number,
    HealthCritThreshold: number,
    HealthFullColor:    Color3,
    HealthWarnColor:    Color3,
    HealthCritColor:    Color3,

    AspectBorderColor:  {[AspectTypes.AspectId]: Color3},

    PostureWarnThreshold: number,
    PostureWarnColor:   Color3,

    ManaBarWidthScale:      number,
    LuminanceBarWidthScale: number,
    LuminanceColor:         Color3,
}

local HUDTheme: HUDTheme = {
    HUD_BOTTOM_OFFSET = 90,
    BarWidth          = 300,
    HealthBarHeight   = 16,
    AmbientBarHeight  =  5,
    BarGap            =  3,

    HealthWarnThreshold = 0.40,
    HealthCritThreshold = 0.15,
    HealthFullColor  = Color3.fromRGB(212, 164,  80),
    HealthWarnColor  = Color3.fromRGB(255, 190,  80),
    HealthCritColor  = Color3.fromRGB(205,  80,  60),

    AspectBorderColor = {
        Ash    = Color3.fromRGB(160, 100,  40),
        Tide   = Color3.fromRGB( 45, 135, 190),
        Ember  = Color3.fromRGB(220,  80,  40),
        Gale   = Color3.fromRGB(190, 190,  90),
        Void   = Color3.fromRGB(120,  50, 170),
        Marrow = Color3.fromRGB(145,  55,  55),
    },

    PostureWarnThreshold = 0.70,
    PostureWarnColor     = Color3.fromRGB(180, 80, 60),

    ManaBarWidthScale      = 0.67,
    LuminanceBarWidthScale = 0.50,
    LuminanceColor         = Color3.fromRGB(200, 175, 100),
}

return HUDTheme
