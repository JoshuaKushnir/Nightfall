--!strict
-- Class: GrassGrid
-- Description: Reusable grid-based grass rendering system.
-- Dependencies: RunService, Workspace, AssetService

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

local GrassTypes = require(game:GetService("ReplicatedStorage").Shared.types.GrassTypes)
type GrassConfig = GrassTypes.GrassConfig

type BladeInfo = {
	Part: BasePart,
	BaseCFrame: CFrame,
	Phase: number,
	HeightScale: number,
}

type Cell = {
	Blades: { BladeInfo },
	X: number,
	Z: number,
}

local GrassGrid = {}
GrassGrid.__index = GrassGrid

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

function GrassGrid.new(config: GrassConfig)
	local self = setmetatable({}, GrassGrid)
	self.Config = config

	self._clock = 0.0
	self._activeCells = {} :: { [string]: Cell }
	self._bladePool = {} :: { BasePart }
	self._lastGridCx = nil :: number?
	self._lastGridCz = nil :: number?

	self._lastWindChange = 0.0
	self._windAngle = 0.0
	self._windStrength = 12.0
	self._windTargetAngle = 0.0
	self._windTargetStrength = 12.0
	self._windRng = Random.new()

	self._bladeFolder = Instance.new("Folder")
	self._bladeFolder.Name = "GrassGrid"
	self._bladeFolder.Parent = Workspace

	self._template = nil :: BasePart?
	self._cellTemplate = nil :: Folder?
	self._connection = nil :: RBXScriptConnection?

	self._targetPlayer = nil :: Player?

	return self
end

function GrassGrid:_buildBladeMesh(): BasePart?
	local config = self.Config
	local success, result = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local vIds = {}
		for i = 0, config.BladeSegments do
			local t = i / config.BladeSegments
			local y = t * config.BladeHeight
			local width = config.BladeWidth * (1 - t)
			local depth = config.BladeDepth * (1 - t)
			local pL = Vector3.new(-width, y, -depth * 0.5)
			local pC = Vector3.new(0,      y,  depth * 0.5)
			local pR = Vector3.new( width, y, -depth * 0.5)
			local vidRow = {}
			vidRow[1] = em:AddVertex(pL)
			vidRow[2] = em:AddVertex(pC)
			vidRow[3] = em:AddVertex(pR)
			vIds[i] = vidRow
		end
		for i = 0, config.BladeSegments - 1 do
			local row0 = vIds[i]
			local row1 = vIds[i+1]
			local v0_L, v0_C, v0_R = row0[1], row0[2], row0[3]
			local v1_L, v1_C, v1_R = row1[1], row1[2], row1[3]
			em:AddTriangle(v0_L, v0_C, v1_C)
			em:AddTriangle(v0_L, v1_C, v1_L)
			em:AddTriangle(v0_C, v0_R, v1_R)
			em:AddTriangle(v0_C, v1_R, v1_C)
		end
		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		em.Parent = mp
		return mp
	end)
	if not success then return nil end
	local mp = result :: MeshPart
	mp.Name = "Blade"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CastShadow = false
	mp.DoubleSided = true
	mp.Material = Enum.Material.SmoothPlastic
	mp.Color = Color3.fromRGB(80, 140, 60)
	return mp
end

function GrassGrid:_buildSimpleBlade(): BasePart
	local p = Instance.new("Part")
	p.Name = "SimpleBlade"
	p.Size = Vector3.new(self.Config.BladeWidth, self.Config.BladeHeight, self.Config.BladeDepth)
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Grass
	p.Color = Color3.fromHSV(0.3, 0.6, 0.5)
	return p
end

function GrassGrid:_allocateCellBlades()
	if not self._cellTemplate then
		if not self._template then
			self._template = self:_buildBladeMesh() or self:_buildSimpleBlade()
		end
		self._cellTemplate = Instance.new("Folder")
		for i = 1, self.Config.BladesPerCell do
			local p = self._template:Clone()
			p.Parent = self._cellTemplate
		end
	end

	local batch = self._cellTemplate:Clone()
	for _, child in ipairs(batch:GetChildren()) do
		child.Parent = self._bladeFolder
		table.insert(self._bladePool, child)
	end
	batch:Destroy()
end

function GrassGrid:_getCellKey(cx: number, cz: number): string
	return cx .. ":" .. cz
end

function GrassGrid:_createCell(cx: number, cz: number): Cell
	local config = self.Config
	local rng = seededRandom(cx, cz)
	local cellInfo: Cell = {
		X = cx,
		Z = cz,
		Blades = {}
	}

	local baseX = cx * config.CellSize
	local baseZ = cz * config.CellSize

	if #self._bladePool < config.BladesPerCell then
		self:_allocateCellBlades()
	end

	for i = 1, config.BladesPerCell do
		local part = table.remove(self._bladePool) :: BasePart

		local lx = rng:NextNumber(-config.CellSize/2, config.CellSize/2)
		local lz = rng:NextNumber(-config.CellSize/2, config.CellSize/2)
		local x = baseX + lx
		local z = baseZ + lz
		local y = config.YOffset

		local rotY = rng:NextNumber(0, math.pi * 2)
		local hScale = rng:NextNumber(0.85, 1.35)
		local hue = rng:NextNumber(config.GrassHueMin, config.GrassHueMax)
		local sat = rng:NextNumber(config.GrassSatMin, config.GrassSatMax)
		local val = rng:NextNumber(config.GrassValMin, config.GrassValMax)

		part.Color = Color3.fromHSV(hue, sat, val)
		part.Size = Vector3.new(config.BladeWidth, config.BladeHeight * hScale, config.BladeDepth)

		local rootY = y - 0.2
		local baseCF = CFrame.new(x, rootY, z) * CFrame.Angles(0, rotY, 0)
		local halfHeight = (config.BladeHeight * hScale * 0.5)
		part.CFrame = baseCF * CFrame.new(0, halfHeight, 0)
		part.Transparency = 0

		table.insert(cellInfo.Blades, {
			Part = part,
			BaseCFrame = baseCF,
			Phase = rng:NextNumber(0, 100),
			HeightScale = hScale,
		})
	end

	return cellInfo
end

function GrassGrid:_removeCell(key: string)
	local cell = self._activeCells[key]
	if not cell then return end

	for _, bInfo in ipairs(cell.Blades) do
		bInfo.Part.CFrame = CFrame.new(0, -10000, 0)
		table.insert(self._bladePool, bInfo.Part)
	end

	self._activeCells[key] = nil
end

function GrassGrid:_updateGrid(playerPos: Vector3)
	local config = self.Config
	local px = playerPos.X
	local pz = playerPos.Z

	local cx = math.floor(px / config.CellSize + 0.5)
	local cz = math.floor(pz / config.CellSize + 0.5)

	if self._lastGridCx == cx and self._lastGridCz == cz then
		return
	end
	self._lastGridCx = cx
	self._lastGridCz = cz

	local range = math.ceil(config.DrawDistance / config.CellSize) + 1
	local bufferDistSq = (config.DrawDistance + config.CellSize) ^ 2
	local needed = {}
	for dx = -range, range do
		for dz = -range, range do
			if (dx*dx + dz*dz) * (config.CellSize*config.CellSize) <= bufferDistSq then
				local k = self:_getCellKey(cx + dx, cz + dz)
				needed[k] = {x = cx + dx, z = cz + dz}
			end
		end
	end

	for k, _ in pairs(self._activeCells) do
		if not needed[k] then
			self:_removeCell(k)
		end
	end

	for k, pos in pairs(needed) do
		if not self._activeCells[k] then
			self._activeCells[k] = self:_createCell(pos.x, pos.z)
		end
	end
end

function GrassGrid:_pickNewWindTarget()
	local config = self.Config
	self._windTargetAngle = self._windRng:NextNumber() * math.pi * 2
	self._windTargetStrength = config.WindStrengthMin + self._windRng:NextNumber() * (config.WindStrengthMax - config.WindStrengthMin)
end

function GrassGrid:_updateWind(dt: number)
	local k = 1 - math.exp(-dt * 0.8)
	local da = (self._windTargetAngle - self._windAngle + math.pi * 3) % (math.pi * 2) - math.pi
	self._windAngle = self._windAngle + da * k
	self._windStrength = self._windStrength + (self._windTargetStrength - self._windStrength) * k
end

function GrassGrid:_updateBlades(dt: number, playerPos: Vector3)
	local config = self.Config
	local t = self._clock

	local windDir = Vector3.new(math.cos(self._windAngle), 0, math.sin(self._windAngle))
	local windAxis = Vector3.new(-windDir.Z, 0, windDir.X)

	local interactRadiusSq = config.InteractionRadius * config.InteractionRadius
	local animDistSq = config.AnimationDist * config.AnimationDist
	local fadeRange = math.max(0.1, config.DrawDistance - config.FadeStart)

	local bulkParts = {}
	local bulkCFrames = {}
	local count = 0
	
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or playerPos
	local camLook = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)

	for _, cell in pairs(self._activeCells) do
		local cellX = cell.X * config.CellSize
		local cellZ = cell.Z * config.CellSize
		
		local cellDx = cellX - playerPos.X
		local cellDz = cellZ - playerPos.Z
		
		-- Cull cells way beyond draw distance (buffer included)
		if (cellDx*cellDx + cellDz*cellDz) > (config.DrawDistance + config.CellSize)^2 + 400 then
			continue
		end
		
		-- Frustum Culling: Skip cells behind the camera to drastically reduce math overhead
		local toCamX = cellX - camPos.X
		local toCamZ = cellZ - camPos.Z
		local distToCamSq = toCamX*toCamX + toCamZ*toCamZ
		
		if distToCamSq > (config.CellSize * config.CellSize * 2) then
			local distToCam = math.sqrt(distToCamSq)
			local dirX = toCamX / distToCam
			local dirZ = toCamZ / distToCam
			local dot = camLook.X * dirX + camLook.Z * dirZ
			if dot < -0.25 then -- ~105 degree threshold, wide enough to hide edges
				continue
			end
		end

		for _, blade in ipairs(cell.Blades) do
			local baseCF = blade.BaseCFrame
			local pos = baseCF.Position

			local dx = pos.X - playerPos.X
			local dz = pos.Z - playerPos.Z
			local distSq = dx*dx + dz*dz

			local fade = 0
			local dist = 0
			
			-- Out of animation range: only sink, no wind or interaction
			if distSq > animDistSq then
				dist = math.sqrt(distSq)
				if dist > config.FadeStart then
					fade = clamp((dist - config.FadeStart) / fadeRange, 0, 1)
				end
			
				local halfHeight = (config.BladeHeight * blade.HeightScale * 0.5)
				local sinkOffset = fade * (config.BladeHeight * blade.HeightScale)
				local finalCF = baseCF * CFrame.new(0, halfHeight - sinkOffset, 0)

				count = count + 1
				bulkParts[count] = blade.Part
				bulkCFrames[count] = finalCF
				continue
			end

			dist = math.sqrt(distSq)
			if dist > config.FadeStart then
				fade = clamp((dist - config.FadeStart) / fadeRange, 0, 1)
			end

			local swayX = pos.X + blade.Phase
			local swayZ = pos.Z + blade.Phase

			-- Optimized wind math using Trig instead of math.noise
			local n = math.sin(swayX * config.WindNoiseScale + t * config.WindNoiseTime) * 
			          math.cos(swayZ * config.WindNoiseScale + t * config.WindNoiseTime * 0.8)
			local gust = math.sin(swayX * 0.02 + t * config.WindGustFreq)
			
			local totalWind = (n * 0.8 + gust * 0.4) * self._windStrength
			local windTilt = math.rad(totalWind)

			local interactRot = CFrame.new()

			if distSq < interactRadiusSq then
				local safeDist = dist
				if safeDist < 0.1 then safeDist = 0.1 end

				local pushFactor = (1 - (safeDist / config.InteractionRadius)) * config.InteractionStrength
				pushFactor = math.pow(pushFactor, 2.0)

				local dirX = dx / safeDist
				local dirZ = dz / safeDist

				local pushAxis = Vector3.new(-dirZ, 0, dirX)
				if pushAxis.Magnitude > 0.001 then
					interactRot = CFrame.fromAxisAngle(pushAxis.Unit, -pushFactor)
				end
			end

			local halfHeight = (config.BladeHeight * blade.HeightScale * 0.5)
			local sinkOffset = fade * (config.BladeHeight * blade.HeightScale)

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

function GrassGrid:SetSurfaces(surfaces: {BasePart})
	self.Config.SurfaceFilter = surfaces
end

function GrassGrid:Start(player: Player)
	self._targetPlayer = player

	self:_pickNewWindTarget()

	self._connection = RunService.Heartbeat:Connect(function(dt)
		self._clock = self._clock + dt

		if self._clock - self._lastWindChange > self.Config.WindChangeInterval then
			self:_pickNewWindTarget()
			self._lastWindChange = self._clock
		end

		self:_updateWind(dt)

		if self._targetPlayer and self._targetPlayer.Character and self._targetPlayer.Character.PrimaryPart then
			local pos = self._targetPlayer.Character.PrimaryPart.Position
			self:_updateGrid(pos)
			self:_updateBlades(dt, pos)
		end
	end)
end

function GrassGrid:Stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end

	for k, _ in pairs(self._activeCells) do
		self:_removeCell(k)
	end

	if self._bladeFolder then
		self._bladeFolder:Destroy()
	end
end

return GrassGrid
