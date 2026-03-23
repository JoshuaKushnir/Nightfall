--!strict
-- Class: HeavenEnvironmentController
-- Description: Manages ethereal Heaven environment with post-processing, clouds, and instantiates the GrassGrid.
-- Dependencies: RunService, Lighting, Workspace, Players

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrassTypes = require(ReplicatedStorage.Shared.types.GrassTypes)
local GrassGrid = require(script.Parent.Parent.modules.environment.GrassGrid)

local HeavenEnvironmentController = {}

-- Constants
local HEAVEN_GRASS_CONFIG: GrassTypes.GrassConfig = {
	YOffset = 10000,
	BladeHeight = 1.2,
	BladeWidth = 0.15,
	BladeDepth = 0.10,
	BladeSegments = 3,

	CellSize = 12.0,
	DrawDistance = 160,
	AnimationDist = 80,
	FadeStart = 120,
	BladesPerCell = 200,
	InteractionRadius = 5.0,
	InteractionStrength = 1.8,

	WindChangeInterval = 5.0,
	WindStrengthMin = 6.0,
	WindStrengthMax = 22.0,
	WindNoiseScale = 0.06,
	WindNoiseTime = 0.35,
	WindGustFreq = 0.9,

	GrassHueMin = 0.27,
	GrassHueMax = 0.36,
	GrassSatMin = 0.55,
	GrassSatMax = 0.85,
	GrassValMin = 0.40,
	GrassValMax = 0.70,
	SurfaceFilter = nil,
}

local CLOUD_PULSE_SPEED = 0.018
local CLOUD_COVER_BASE = 0.82
local CLOUD_COVER_AMP = 0.15
local CLOUD_DENSITY_BASE = 0.85
local CLOUD_DENSITY_AMP = 0.12
local SUN_GLARE_ANGLE = 35
local SUN_GLARE_ANGLE2 = 10
local FLARE_MAX_ALPHA = 0.55

-- State
local _initialized = false
local _clock = 0.0

local _sunRaysEffect: SunRaysEffect?
local _bloomEffect: BloomEffect?
local _clouds: Clouds?
local _lensFlareGui: ScreenGui?

local _grassGrid = GrassGrid.new(HEAVEN_GRASS_CONFIG)
local _connection: RBXScriptConnection?

-- Helpers
local function clamp(val: number, minVal: number, maxVal: number): number
	if val < minVal then return minVal end
	if val > maxVal then return maxVal end
	return val
end

local function updateClouds(t: number)
	if not _clouds then return end
	local pulse = math.sin(t * CLOUD_PULSE_SPEED)
	_clouds.Cover = CLOUD_COVER_BASE + pulse * CLOUD_COVER_AMP
	_clouds.Density = CLOUD_DENSITY_BASE + pulse * CLOUD_DENSITY_AMP
end

local function getSunDirection(): Vector3
	local timeOfDay = Lighting.ClockTime
	local hours = timeOfDay - 6
	local angle = (hours / 12) * math.pi
	local sunDir = CFrame.Angles(0, Lighting.GeographicLatitude * math.pi / 180, 0)
		* CFrame.Angles(angle, 0, 0)
		* Vector3.new(0, -1, 0)
	return sunDir.Unit
end

local function buildLensFlareUI()
	local player = Players.LocalPlayer
	if not player then return end
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	if not playerGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HeavenLensFlare"
	gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false

	local halo = Instance.new("ImageLabel")
	halo.Name = "Halo"; halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Size = UDim2.new(0.8, 0, 0.8, 0); halo.Position = UDim2.new(0.5, 0, 0.5, 0)
	halo.BackgroundTransparency = 1; halo.Image = "rbxassetid://1114214539"
	halo.ImageColor3 = Color3.fromRGB(255, 235, 180); halo.ImageTransparency = 1
	halo.ScaleType = Enum.ScaleType.Fit; halo.ZIndex = 10; halo.Parent = gui

	local streak = Instance.new("ImageLabel")
	streak.Name = "Streak"; streak.AnchorPoint = Vector2.new(0.5, 0.5)
	streak.Size = UDim2.new(1.4, 0, 1.4, 0); streak.Position = UDim2.new(0.5, 0, 0.5, 0)
	streak.BackgroundTransparency = 1; streak.Image = "rbxassetid://6023426952"
	streak.ImageColor3 = Color3.fromRGB(200, 225, 255); streak.ImageTransparency = 1
	streak.Rotation = 45; streak.ZIndex = 11; streak.Parent = gui
	_lensFlareGui = gui
end

local function updateSunEffect()
	if not _sunRaysEffect then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local sunDir   = getSunDirection()
	local camDir   = camera.CFrame.LookVector
	local dot      = camDir:Dot(sunDir)
	local angleDeg = math.deg(math.acos(clamp(dot, -1, 1)))
	local t = 1 - clamp((angleDeg - SUN_GLARE_ANGLE2) / (SUN_GLARE_ANGLE - SUN_GLARE_ANGLE2), 0, 1)
	t = t * t
	_sunRaysEffect.Intensity = 0.05 + t * 0.85
	_sunRaysEffect.Spread    = 0.4  + t * 0.35
	if _bloomEffect then
		_bloomEffect.Intensity = clamp(0.4 + t * 0.7, 0, 1)
		_bloomEffect.Threshold = clamp(1.5 - t * 0.6, 0, 2)
	end
	if _lensFlareGui then
		local halo   = _lensFlareGui:FindFirstChild("Halo")
		local streak2 = _lensFlareGui:FindFirstChild("Streak")
		local alpha  = 1 - t * FLARE_MAX_ALPHA
		if halo    then halo.ImageTransparency    = alpha end
		if streak2 then streak2.ImageTransparency = alpha + 0.18 end
	end
end

local function setupPostProcessing()
	local sr = Lighting:FindFirstChildOfClass("SunRaysEffect")         or Instance.new("SunRaysEffect",         Lighting)
	sr.Intensity = 0.05; sr.Spread = 0.5; _sunRaysEffect = sr

	local bl = Lighting:FindFirstChildOfClass("BloomEffect")            or Instance.new("BloomEffect",            Lighting)
	bl.Intensity = 0.5; bl.Size = 30; bl.Threshold = 1.5; _bloomEffect = bl

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")  or Instance.new("ColorCorrectionEffect",  Lighting)
	cc.Brightness = 0.08; cc.Contrast = 0.08; cc.Saturation = 0.15; cc.TintColor = Color3.fromRGB(255, 250, 240)

	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")    or Instance.new("DepthOfFieldEffect",    Lighting)
	dof.FarIntensity = 0.15; dof.NearIntensity = 0.0; dof.FocusDistance = 80; dof.InFocusRadius = 40

	local atm = Lighting:FindFirstChildOfClass("Atmosphere")            or Instance.new("Atmosphere",            Lighting)
	atm.Density = 0.25; atm.Offset = 0.1; atm.Haze = 0.0; atm.Glare = 0.5; atm.Color = Color3.fromRGB(220, 230, 245)
end

function HeavenEnvironmentController:Init()
	_clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	_initialized = true
end

function HeavenEnvironmentController:Start()
	if not _initialized then warn("[HeavenEnv] Not initialized"); return end

	_clouds = _clouds or Workspace.Terrain:FindFirstChildOfClass("Clouds")
	setupPostProcessing()
	buildLensFlareUI()

	task.defer(function()
		local player = Players.LocalPlayer
		if player then
			_grassGrid:Start(player)
		end
		
		_connection = RunService.Heartbeat:Connect(function(dt: number)
			_clock = _clock + dt
			updateClouds(_clock)
			updateSunEffect()
		end)
		print("[HeavenEnv] Started with decoupled GrassGrid system.")
	end)
end

function HeavenEnvironmentController:Stop()
	if _connection then _connection:Disconnect(); _connection = nil end
	_grassGrid:Stop()
	if _lensFlareGui then _lensFlareGui:Destroy(); _lensFlareGui = nil end
end

return HeavenEnvironmentController
