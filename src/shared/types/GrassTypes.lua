--!strict
-- Class: GrassTypes
-- Description: Shared types for the GrassGrid module.
-- Dependencies: None

export type GrassConfig = {
    YOffset: number,
    BladeHeight: number,
    BladeWidth: number,
    BladeDepth: number,
    BladeSegments: number,
    BladesPerClump: number?,
    CurveStrength: number?,
    RootColor: Color3?,
    TipColor: Color3?,

    CellSize: number,
    DrawDistance: number,
    AnimationDist: number,
    FadeStart: number,
    BladesPerCell: number,
    InteractionRadius: number,
    InteractionStrength: number,

    WindChangeInterval: number,
    WindStrengthMin: number,
    WindStrengthMax: number,
    WindNoiseScale: number,
    WindNoiseTime: number,
    WindGustFreq: number,

    GrassHueMin: number,
    GrassHueMax: number,
    GrassSatMin: number,
    GrassSatMax: number,
    GrassValMin: number,
    GrassValMax: number,
	SurfaceFilter: {BasePart}?, -- Optional list of surfaces to place grass on
}

return {}
