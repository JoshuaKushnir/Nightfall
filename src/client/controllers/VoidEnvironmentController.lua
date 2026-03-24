--!strict
-- Class: VoidEnvironmentController
-- Description: Stub controller to verify GrassGrid reusability.
-- Dependencies: GrassGrid, GrassTypes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local GrassTypes = require(ReplicatedStorage.Shared.types.GrassTypes)
local GrassGrid = require(script.Parent.Parent.modules.environment.GrassGrid)

local VOID_GRASS_CONFIG: GrassTypes.GrassConfig = {
	YOffset = -500,
	BladeHeight = 0.8,
	BladeWidth = 0.1,
	BladeDepth = 0.05,
	BladeSegments = 2,
	BladesPerClump = 3,
	CurveStrength = 0.15,
	CellSize = 10.0,
	DrawDistance = 100,
	AnimationDist = 50,
	FadeStart = 80,
	BladesPerCell = 15,
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
local _connection: RBXScriptConnection?

function VoidEnvironmentController:Start(player: Player)
	_grassGrid:Start(player)

	_connection = RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			local camPos = cam.CFrame.Position
			for _, emitter in ipairs(CollectionService:GetTagged("AmbientEmitter")) do
				if emitter:IsA("ParticleEmitter") and emitter.Parent then
					local pos
					if emitter.Parent:IsA("BasePart") then
						pos = emitter.Parent.Position
					elseif emitter.Parent:IsA("Attachment") then
						pos = emitter.Parent.WorldPosition
					end
					if pos then
						local dist = (camPos - pos).Magnitude
						emitter.Enabled = (dist <= 100)
					end
				end
			end
		end
	end)
end

function VoidEnvironmentController:Stop()
	if _connection then
		_connection:Disconnect()
		_connection = nil
	end
	_grassGrid:Stop()
end

return VoidEnvironmentController
