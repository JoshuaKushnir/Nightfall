--!strict
-- Class: VoidEnvironmentController
-- Description: Stub controller to verify GrassGrid reusability.
-- Dependencies: GrassGrid, GrassTypes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GrassTypes = require(ReplicatedStorage.Shared.types.GrassTypes)
local GrassGrid = require(script.Parent.Parent.Parent.modules.environment.GrassGrid)

local VOID_GRASS_CONFIG: GrassTypes.GrassConfig = {
	YOffset = -500,
	BladeHeight = 0.8,
	BladeWidth = 0.1,
	BladeDepth = 0.05,
	BladeSegments = 2,
	CellSize = 10.0,
	DrawDistance = 100,
	AnimationDist = 50,
	FadeStart = 80,
	BladesPerCell = 50,
	InteractionRadius = 4.0,
	InteractionStrength = 1.0,
	WindChangeInterval = 3.0,
	WindStrengthMin = 2.0,
	WindStrengthMax = 8.0,
	WindNoiseScale = 0.1,
	WindNoiseTime = 0.5,
	WindGustFreq = 1.2,
	GrassHueMin = 0.7,
	GrassHueMax = 0.8,
	GrassSatMin = 0.4,
	GrassSatMax = 0.6,
	GrassValMin = 0.2,
	GrassValMax = 0.4,
	SurfaceFilter = nil,
}

local VoidEnvironmentController = {}

local _grassGrid = GrassGrid.new(VOID_GRASS_CONFIG)

function VoidEnvironmentController:Start(player: Player)
	_grassGrid:Start(player)
end

function VoidEnvironmentController:Stop()
	_grassGrid:Stop()
end

return VoidEnvironmentController
