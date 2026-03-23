--!strict
-- Class: HeavenEnvironmentController
-- Description: Manages ethereal Heaven environment with post-processing and a static, dense grass grid
--              that parts when the player walks through it.
-- Dependencies: RunService, Lighting, Workspace, Players, AssetService

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local AssetService = game:GetService("AssetService")

local HeavenEnvironmentController = {}

-- Constants
local HEAVEN_Y = 10000
local BLADE_HEIGHT = 1.2
local BLADE_WIDTH = 0.15
local BLADE_DEPTH = 0.10
local BLADE_SEGMENTS = 3

-- Grid / LOD settings
local CELL_SIZE = 12.0
local DRAW_DISTANCE = 160
local ANIMATION_DIST = 80
local FADE_START = 120
local BLADES_PER_CELL = 200
local INTERACTION_RADIUS = 5.0
local INTERACTION_STRENGTH = 1.8

-- Wind settings
local WIND_CHANGE_INTERVAL = 5.0
local WIND_STRENGTH_MIN = 6.0
local WIND_STRENGTH_MAX = 22.0
local WIND_NOISE_SCALE = 0.06
local WIND_NOISE_TIME = 0.35
local WIND_GUST_FREQ = 0.9

-- Visuals
local GRASS_HUE_MIN = 0.27
local GRASS_HUE_MAX = 0.36
local GRASS_SAT_MIN = 0.55
local GRASS_SAT_MAX = 0.85
local GRASS_VAL_MIN = 0.40
local GRASS_VAL_MAX = 0.70

local CLOUD_PULSE_SPEED = 0.018
local CLOUD_COVER_BASE = 0.82
local CLOUD_COVER_AMP = 0.15
local CLOUD_DENSITY_BASE = 0.85
local CLOUD_DENSITY_AMP = 0.12
local SUN_GLARE_ANGLE = 35
local SUN_GLARE_ANGLE2 = 10
local FLARE_MAX_ALPHA = 0.55

-- Types
export type BladeInfo = {
	Part: BasePart,
	BaseCFrame: CFrame, -- The static home position
	Phase: number,
	HeightScale: number,
}

export type Cell = {
	Blades: { BladeInfo },
	X: number,
	Z: number,
}

-- State
local _initialized = false
local _connections: { RBXScriptConnection } = {}
local _clock = 0.0
local _bladeFolder: Folder?
local _activeCells: { [string]: Cell } = {}
local _bladePool: { BasePart } = {} -- Pool of unused parts

local _lastWindChange = 0.0
local _windAngle = 0.0
local _windStrength = 12.0
local _windTargetAngle = 0.0
local _windTargetStrength = 12.0

local _sunRaysEffect: SunRaysEffect?
local _bloomEffect: BloomEffect?
local _clouds: Clouds?
local _lensFlareGui: ScreenGui?

-- Helpers
local function clamp(val: number, minVal: number, maxVal: number): number
	if val < minVal then return minVal end
	if val > maxVal then return maxVal end
	return val
end

local function seededRandom(x: number, z: number): Random
	local seed = (x * 73856093) + (z * 19349663)
	return Random.new(seed)
end

-- Geometry Generation
local function buildBladeMesh(): BasePart?
	local success, result = pcall(function()
		local em = AssetService:CreateEditableMesh()

		-- Geometry: V-Shaped Blade
		-- Cross-section:   \ v /
		-- Spine (center) is pushed back or forward.
		-- To look like a grass blade, the spine usually protrudes.

		local vIds = {}

		-- Generate rows
		for i = 0, BLADE_SEGMENTS do
			local t = i / BLADE_SEGMENTS -- 0 (bottom) to 1 (top)
			local y = t * BLADE_HEIGHT
			local width = BLADE_WIDTH * (1 - t) -- Linear taper to point
			local depth = BLADE_DEPTH * (1 - t)

			-- Bending curve (simple quadratic curve back for natural droop if we wanted,
			-- but straight is fine for vertex shader style manipulation,
			-- here we do static geometry so straight up is safer for CFrame rotation)

			-- V-Shape Profile
			-- Left(-w, -d), Center(0, d), Right(w, -d)
			-- This makes the spine pop OUT (positive Z) relative to edges.

			local pL = Vector3.new(-width, y, -depth * 0.5)
			local pC = Vector3.new(0,      y,  depth * 0.5)
			local pR = Vector3.new( width, y, -depth * 0.5)

			local vidRow = {}
			vidRow[1] = em:AddVertex(pL)
			vidRow[2] = em:AddVertex(pC)
			vidRow[3] = em:AddVertex(pR)

			vIds[i] = vidRow
		end

		-- Build Faces
		for i = 0, BLADE_SEGMENTS - 1 do
			local row0 = vIds[i]
			local row1 = vIds[i+1]

			-- Vertices indices
			local v0_L, v0_C, v0_R = row0[1], row0[2], row0[3]
			local v1_L, v1_C, v1_R = row1[1], row1[2], row1[3]

			-- Left Wing (Left -> Center)
			em:AddTriangle(v0_L, v0_C, v1_C)
			em:AddTriangle(v0_L, v1_C, v1_L)

			-- Right Wing (Center -> Right)
			em:AddTriangle(v0_C, v0_R, v1_R)
			em:AddTriangle(v0_C, v1_R, v1_C)
		end

		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		em.Parent = mp -- Keep editable mesh alive
		return mp
	end)

	if not success then return nil end

	local mp = result :: MeshPart
	mp.Name = "Blade"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CastShadow = false
	mp.DoubleSided = true -- Important for visibility
	mp.Material = Enum.Material.SmoothPlastic
	mp.Color = Color3.fromRGB(80, 140, 60)
	return mp
end

local function buildSimpleBlade(): BasePart
	local p = Instance.new("Part")
	p.Name = "BladeFallback"
	p.Size = Vector3.new(0.3, 2.2, 0.3)
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = Enum.Material.Grass
	p.Color = Color3.fromRGB(80, 140, 60)
	return p
end

local _template: BasePart? = nil

-- Grid Logic
local function getCellKey(cx: number, cz: number): string
	return cx .. ":" .. cz
end

local function createCell(cx: number, cz: number): Cell
	local rng = seededRandom(cx, cz)
	local cellInfo: Cell = {
		X = cx,
		Z = cz,
		Blades = {}
	}

	local baseX = cx * CELL_SIZE
	local baseZ = cz * CELL_SIZE

	for i = 1, BLADES_PER_CELL do
		local part: BasePart
		if #_bladePool > 0 then
			part = table.remove(_bladePool) :: BasePart
		else
			if not _template then
				_template = buildBladeMesh() or buildSimpleBlade()
			end
			part = _template:Clone()
			part.Parent = _bladeFolder
		end

		local lx = rng:NextNumber(-CELL_SIZE/2, CELL_SIZE/2)
		local lz = rng:NextNumber(-CELL_SIZE/2, CELL_SIZE/2)
		local x = baseX + lx
		local z = baseZ + lz
		local y = HEAVEN_Y

		local rotY = rng:NextNumber(0, math.pi * 2)
		local hScale = rng:NextNumber(0.85, 1.35) -- Slightly taller variation
		local hue = rng:NextNumber(GRASS_HUE_MIN, GRASS_HUE_MAX)
		local sat = rng:NextNumber(GRASS_SAT_MIN, GRASS_SAT_MAX)
		local val = rng:NextNumber(GRASS_VAL_MIN, GRASS_VAL_MAX)

		part.Color = Color3.fromHSV(hue, sat, val)
		part.Size = Vector3.new(BLADE_WIDTH, BLADE_HEIGHT * hScale, BLADE_DEPTH)

		-- Define Root CFrame (at ground level)
		local rootY = y - 0.2
		local baseCF = CFrame.new(x, rootY, z) * CFrame.Angles(0, rotY, 0)

		-- Initial placement (MeshPart position is center, so move up by half height)
		local halfHeight = (BLADE_HEIGHT * hScale * 0.5)
		part.CFrame = baseCF * CFrame.new(0, halfHeight, 0)
		part.Transparency = 0

		table.insert(cellInfo.Blades, {
			Part = part,
			BaseCFrame = baseCF, -- Storing the ROOT CFrame
			Phase = rng:NextNumber(0, 100),
			HeightScale = hScale,
		})
	end

	return cellInfo
end

local function removeCell(key: string)
	local cell = _activeCells[key]
	if not cell then return end

	for _, bInfo in ipairs(cell.Blades) do
		bInfo.Part.CFrame = CFrame.new(0, -10000, 0)
		table.insert(_bladePool, bInfo.Part)
	end

	_activeCells[key] = nil
end

local function updateGrid(playerPos: Vector3)
	local px = playerPos.X
	local pz = playerPos.Z

	local cx = math.floor(px / CELL_SIZE + 0.5)
	local cz = math.floor(pz / CELL_SIZE + 0.5)
	local range = math.ceil(DRAW_DISTANCE / CELL_SIZE)

	local needed = {}
	for dx = -range, range do
		for dz = -range, range do
			if (dx*dx + dz*dz) * (CELL_SIZE*CELL_SIZE) <= DRAW_DISTANCE*DRAW_DISTANCE then
				local k = getCellKey(cx + dx, cz + dz)
				needed[k] = {x = cx + dx, z = cz + dz}
			end
		end
	end

	for k, _ in pairs(_activeCells) do
		if not needed[k] then
			removeCell(k)
		end
	end

	for k, pos in pairs(needed) do
		if not _activeCells[k] then
			_activeCells[k] = createCell(pos.x, pos.z)
		end
	end
end

-- Animation / Interaction
local function updateBlades(dt: number, playerPos: Vector3)
	local t = _clock

	local windDir = Vector3.new(math.cos(_windAngle), 0, math.sin(_windAngle))
	local windAxis = Vector3.new(-windDir.Z, 0, windDir.X) -- Perpendicular to wind dir

	local interactRadiusSq = INTERACTION_RADIUS * INTERACTION_RADIUS
	local animDistSq = ANIMATION_DIST * ANIMATION_DIST

	-- Arrays for BulkMoveTo (Optimization)
	local bulkParts = {}
	local bulkCFrames = {}
	local count = 0

	for _, cell in pairs(_activeCells) do
		-- Optimization: Quick cell distance check
		local cellDx = (cell.X * CELL_SIZE) - playerPos.X
		local cellDz = (cell.Z * CELL_SIZE) - playerPos.Z

		-- Skip cells entirely if they are way out of draw distance
		if (cellDx*cellDx + cellDz*cellDz) > (animDistSq + 400) then
			continue
		end

		for _, blade in ipairs(cell.Blades) do
			local baseCF = blade.BaseCFrame
			local pos = baseCF.Position -- Root position

			-- Distance check for individual blade animation
			local dx = pos.X - playerPos.X
			local dz = pos.Z - playerPos.Z
			local distSq = dx*dx + dz*dz
			local dist = math.sqrt(distSq)

			-- LOD Sinking
			local fade = 0
			if dist > FADE_START then
				fade = clamp((dist - FADE_START) / (DRAW_DISTANCE - FADE_START), 0, 1)
			end

			if distSq > animDistSq then
				-- If out of animation range, just sink it and skip the rest of the math
				local halfHeight = (BLADE_HEIGHT * blade.HeightScale * 0.5)
				local sinkOffset = fade * (BLADE_HEIGHT * blade.HeightScale)
				local finalCF = baseCF * CFrame.new(0, halfHeight - sinkOffset, 0)

				count = count + 1
				bulkParts[count] = blade.Part
				bulkCFrames[count] = finalCF
				continue
			end

			-- Wind Calculation (Sway)
			-- Use blade phase to offset noise lookup slightly or just rely on position
			local swayX = pos.X + blade.Phase
			local swayZ = pos.Z + blade.Phase

			local n = math.noise(swayX * WIND_NOISE_SCALE, swayZ * WIND_NOISE_SCALE, t * WIND_NOISE_TIME)
			local gust = math.noise(swayX * 0.02, t * WIND_GUST_FREQ, 0)

			-- Oscillate wind: noise returns -0.5 to 0.5 roughly.
			-- We want it to sway back and forth naturally.
			local totalWind = (n * 0.8 + gust * 0.4) * _windStrength
			local windTilt = math.rad(totalWind)

			-- Interaction (Parting)
			local interactRot = CFrame.new()

			if distSq < interactRadiusSq then
				local dist = math.sqrt(distSq)
				if dist < 0.1 then dist = 0.1 end

				local pushFactor = (1 - (dist / INTERACTION_RADIUS)) * INTERACTION_STRENGTH
				-- Quadratic falloff for smoother feel
				pushFactor = math.pow(pushFactor, 2.0)

				-- Direction FROM player TO grass
				local dirX = dx / dist
				local dirZ = dz / dist

				-- Rotate away from player.
				-- Axis is perpendicular to the vector from player to grass.
				local pushAxis = Vector3.new(-dirZ, 0, dirX)
				if pushAxis.Magnitude > 0.001 then
					interactRot = CFrame.fromAxisAngle(pushAxis.Unit, -pushFactor)
				end
			end

			-- Combine Rotations
			local halfHeight = (BLADE_HEIGHT * blade.HeightScale * 0.5)
			local sinkOffset = fade * (BLADE_HEIGHT * blade.HeightScale)

			local combinedRot = interactRot * CFrame.fromAxisAngle(windAxis, windTilt)
			local finalCF = baseCF * combinedRot * CFrame.new(0, halfHeight - sinkOffset, 0)

			count = count + 1
			bulkParts[count] = blade.Part
			bulkCFrames[count] = finalCF
		end
	end

	if count > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Wind management (same as before)
local function pickNewWindTarget()
	_windTargetAngle = math.random() * math.pi * 2
	_windTargetStrength = WIND_STRENGTH_MIN + math.random() * (WIND_STRENGTH_MAX - WIND_STRENGTH_MIN)
end

local function updateWind(dt: number)
	local k = 1 - math.exp(-dt * 0.8)
	local da = (_windTargetAngle - _windAngle + math.pi * 3) % (math.pi * 2) - math.pi
	_windAngle = _windAngle + da * k
	_windStrength = _windStrength + (_windTargetStrength - _windStrength) * k
end

-- Clouds, Sun, Lens Flare, Lifecycle (same as before)
local function updateClouds(t: number)
	if not _clouds then return end
	_clouds.Cover = CLOUD_COVER_BASE + math.sin(t * CLOUD_PULSE_SPEED) * CLOUD_COVER_AMP
	_clouds.Density = CLOUD_DENSITY_BASE + math.cos(t * CLOUD_PULSE_SPEED * 1.3) * CLOUD_DENSITY_AMP
end

local function getSunDirection(): Vector3
	local ok, dir = pcall(function() return Lighting:GetSunDirection() end)
	if ok and dir then return -dir end
	local t = (Lighting.ClockTime / 24) * math.pi * 2
	return Vector3.new(math.cos(t), math.sin(t) * 0.8, 0.2).Unit
end

local function buildLensFlareUI()
	local player = Players.LocalPlayer
	if not player then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "HeavenLensFlare"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player.PlayerGui

	local halo = Instance.new("ImageLabel")
	halo.Name = "Halo"; halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Size = UDim2.new(1.8, 0, 1.8, 0); halo.Position = UDim2.new(0.5, 0, 0.5, 0)
	halo.BackgroundTransparency = 1; halo.Image = "rbxassetid://6023426952"
	halo.ImageColor3 = Color3.fromRGB(255, 248, 210); halo.ImageTransparency = 1
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
	local sunDir = getSunDirection()
	local camDir = camera.CFrame.LookVector
	local dot = camDir:Dot(sunDir)
	local angleDeg = math.deg(math.acos(clamp(dot, -1, 1)))
	local t = 1 - clamp((angleDeg - SUN_GLARE_ANGLE2) / (SUN_GLARE_ANGLE - SUN_GLARE_ANGLE2), 0, 1)
	t = t * t
	_sunRaysEffect.Intensity = 0.05 + t * 0.85
	_sunRaysEffect.Spread = 0.4 + t * 0.35
	if _bloomEffect then
		_bloomEffect.Intensity = clamp(0.4 + t * 0.7, 0, 1)
		_bloomEffect.Threshold = clamp(1.5 - t * 0.6, 0, 2)
	end
	if _lensFlareGui then
		local halo = _lensFlareGui:FindFirstChild("Halo")
		local streak = _lensFlareGui:FindFirstChild("Streak")
		local alpha = 1 - t * FLARE_MAX_ALPHA
		if halo then halo.ImageTransparency = alpha end
		if streak then streak.ImageTransparency = alpha + 0.18 end
	end
end

local function setupPostProcessing()
	local sr = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect", Lighting)
	sr.Intensity = 0.05; sr.Spread = 0.5; _sunRaysEffect = sr
	local bl = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", Lighting)
	bl.Intensity = 0.5; bl.Size = 30; bl.Threshold = 1.5; _bloomEffect = bl
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect", Lighting)
	cc.Brightness = 0.08; cc.Contrast = 0.08; cc.Saturation = 0.15; cc.TintColor = Color3.fromRGB(255, 250, 240)
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Instance.new("DepthOfFieldEffect", Lighting)
	dof.FarIntensity = 0.15; dof.NearIntensity = 0.0; dof.FocusDistance = 80; dof.InFocusRadius = 40
	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
	atm.Density = 0.25; atm.Offset = 0.1; atm.Haze = 0.0; atm.Glare = 0.5; atm.Color = Color3.fromRGB(220, 230, 245)
end

function HeavenEnvironmentController:Init()
	_clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	_initialized = true
end

function HeavenEnvironmentController:Start()
	if not _initialized then warn("[HeavenEnv] Not initialized"); return end
	_bladeFolder = Instance.new("Folder")
	_bladeFolder.Name = "HeavenGrass"
	_bladeFolder.Parent = Workspace
	_clouds = _clouds or Workspace.Terrain:FindFirstChildOfClass("Clouds")
	setupPostProcessing()
	buildLensFlareUI()
	pickNewWindTarget()

	task.defer(function()
		local capOk = false
		for attempt = 1, 10 do
			local ok = pcall(function() local em = AssetService:CreateEditableMesh() end)
			if ok then capOk = true; break end
			task.wait(0.15)
		end
		if not capOk then warn("[HeavenEnv] EditableMesh not available. Using fallback.") end
		task.wait(0.25)

		local conn = RunService.Heartbeat:Connect(function(dt: number)
			_clock = _clock + dt
			local player = Players.LocalPlayer
			local char = player and player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local pos = root.Position
			updateWind(dt)
			updateClouds(_clock)
			updateSunEffect()
			if pos.Y > 8000 then
				updateGrid(pos)
				updateBlades(dt, pos)
			else
				for k, _ in pairs(_activeCells) do removeCell(k) end
			end
			if _clock - _lastWindChange > WIND_CHANGE_INTERVAL then
				pickNewWindTarget(); _lastWindChange = _clock
			end
		end)
		table.insert(_connections, conn)
		print("[HeavenEnv] Started with Grid Grass system.")
	end)
end

function HeavenEnvironmentController:Stop()
	for _, c in ipairs(_connections) do c:Disconnect() end
	table.clear(_connections)
	if _bladeFolder then _bladeFolder:Destroy(); _bladeFolder = nil end
	if _lensFlareGui then _lensFlareGui:Destroy(); _lensFlareGui = nil end
	_activeCells = {}
	_bladePool = {}
	_template = nil
end

return HeavenEnvironmentController
