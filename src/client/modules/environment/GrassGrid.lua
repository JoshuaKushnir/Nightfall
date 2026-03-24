--!strict
--[[
    Class: GrassGrid
    Description: Reusable grid-based grass rendering system for BOTW-style stylized grass.
    Dependencies: RunService, Workspace, AssetService, GrassTypes
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

local GrassTypes = require(game:GetService("ReplicatedStorage").Shared.types.GrassTypes)
export type GrassConfig = GrassTypes.GrassConfig

type BladeInfo = {
	Part: BasePart,
	BaseCFrame: CFrame,
	Phase: number,
	HeightScale: number,
	PushTime: number?,
	PushDir: Vector3?,
	WindWaveOffset: number,
	WindGustOffset: number,
}

type Cell = {
	Blades: { BladeInfo },
	X: number,
	Z: number,
	LastUpdate: number?,
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
	self._flowerPool = {} :: { BasePart }
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
	self._flowerTemplate = nil :: BasePart?
	self._cellTemplate = nil :: Folder?
	self._flowerCellTemplate = nil :: Folder?
	self._connection = nil :: RBXScriptConnection?

	self._targetPlayer = nil :: Player?

	return self
end

-- Builds a proper multi-blade clump mesh (BOTW-style, low vertex count)
function GrassGrid:_buildBladeMesh(): BasePart?
	local config = self.Config
	local success, result = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local vIds = {}

		local numBlades = config.BladesPerClump or 1
		local baseCurve = config.CurveStrength or 0

		-- Use grayscale based on config values so Part.Color can accurately tint both grass and flowers
		local _, _, rV = (config.RootColor or Color3.fromRGB(80, 140, 60)):ToHSV()
		local _, _, tV = (config.TipColor or Color3.fromRGB(180, 220, 80)):ToHSV()
		local rootColor = Color3.fromHSV(0, 0, rV)
		local tipColor = Color3.fromHSV(0, 0, tV)

		for b = 1, numBlades do
			local bladeYaw = (b - 1) * (math.pi * 2 / numBlades)
			local bRadius = (numBlades > 1) and (config.BladeWidth * 0.8) or 0
			local bx = math.cos(bladeYaw) * bRadius
			local bz = math.sin(bladeYaw) * bRadius
			local bRot = CFrame.Angles(0, bladeYaw + math.pi/2, 0)

			local bladeVIds = {}
			for i = 0, config.BladeSegments do
				local t = i / config.BladeSegments
				local y = t * config.BladeHeight
				local curve = baseCurve * (t * t)
				local width = config.BladeWidth * (1 - t)
				local depth = config.BladeDepth * (1 - t)

				local localL = Vector3.new(-width, y, -depth * 0.5 + curve)
				local localC = Vector3.new(0,      y,  depth * 0.5 + curve)
				local localR = Vector3.new( width, y, -depth * 0.5 + curve)

				local pL = Vector3.new(bx, 0, bz) + bRot * localL
				local pC = Vector3.new(bx, 0, bz) + bRot * localC
				local pR = Vector3.new(bx, 0, bz) + bRot * localR

				local vidRow = {}
				vidRow[1] = em:AddVertex(pL)
				vidRow[2] = em:AddVertex(pC)
				vidRow[3] = em:AddVertex(pR)

				local color = rootColor:Lerp(tipColor, t)
				pcall(function()
					em:SetVertexColor(vidRow[1], color)
					em:SetVertexColor(vidRow[2], color)
					em:SetVertexColor(vidRow[3], color)
				end)

				bladeVIds[i] = vidRow
			end
			vIds[b] = bladeVIds
		end

		for b = 1, numBlades do
			local bladeVIds = vIds[b]
			for i = 0, config.BladeSegments - 1 do
				local row0 = bladeVIds[i]
				local row1 = bladeVIds[i+1]
				local v0_L, v0_C, v0_R = row0[1], row0[2], row0[3]
				local v1_L, v1_C, v1_R = row1[1], row1[2], row1[3]
				em:AddTriangle(v0_L, v0_C, v1_C)
				em:AddTriangle(v0_L, v1_C, v1_L)
				em:AddTriangle(v0_C, v0_R, v1_R)
				em:AddTriangle(v0_C, v1_R, v1_C)
			end
		end

		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		return mp
	end)
	if not success then return nil end

	local mp = result :: MeshPart
	mp.Name = "Blade"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CastShadow = false
	pcall(function() mp.DoubleSided = true end)
	mp.Material = Enum.Material.SmoothPlastic
	mp.Color = Color3.fromRGB(255, 255, 255)
	return mp
end

function GrassGrid:_buildFlowerMesh(): BasePart?
	local config = self.Config
	local success, result = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local numPetals = 5
		local h = config.BladeHeight * 0.8
		local w = config.BladeWidth * 1.2
		for b = 1, numPetals do
			local angle = (b - 1) * (math.pi * 2 / numPetals)
			local bRot = CFrame.Angles(0, angle, 0)
			local pL = bRot * Vector3.new(-w/2, h, 0)
			local pC = bRot * Vector3.new(0, 0, 0)
			local pR = bRot * Vector3.new(w/2, h, 0)
			local pT = bRot * Vector3.new(0, h + w/2, 0)

			local vL = em:AddVertex(pL)
			local vC = em:AddVertex(pC)
			local vR = em:AddVertex(pR)
			local vT = em:AddVertex(pT)

			em:AddTriangle(vL, vC, vR)
			em:AddTriangle(vL, vR, vT)

			local color = Color3.fromRGB(200, 200, 200)
			pcall(function()
				em:SetVertexColor(vL, color)
				em:SetVertexColor(vC, Color3.fromRGB(50, 150, 50))
				em:SetVertexColor(vR, color)
				em:SetVertexColor(vT, color)
			end)
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(em))
	end)
	if not success then return nil end
	local mp = result :: MeshPart
	mp.Name = "Flower"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CastShadow = false
	pcall(function() mp.DoubleSided = true end)
	mp.Material = Enum.Material.Neon
	mp.Color = Color3.fromRGB(255, 255, 255)
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
	p.Color = Color3.fromRGB(255, 255, 255)
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
	if not self._flowerCellTemplate then
		if not self._flowerTemplate then
			self._flowerTemplate = self:_buildFlowerMesh() or self:_buildSimpleBlade()
		end
		self._flowerCellTemplate = Instance.new("Folder")
		for i = 1, math.max(1, math.floor(self.Config.BladesPerCell * (self.Config.FlowerProbability or 0.1))) do
			local p = self._flowerTemplate:Clone()
			p.Parent = self._flowerCellTemplate
		end
	end

	local batch = self._cellTemplate:Clone()
	for _, child in ipairs(batch:GetChildren()) do
		child.Parent = self._bladeFolder
		table.insert(self._bladePool, child)
	end
	batch:Destroy()

	local flowerBatch = self._flowerCellTemplate:Clone()
	for _, child in ipairs(flowerBatch:GetChildren()) do
		child.Parent = self._bladeFolder
		table.insert(self._flowerPool, child)
	end
	flowerBatch:Destroy()
end

function GrassGrid:_getCellKey(cx: number, cz: number): string
	return cx .. ":" .. cz
end

function GrassGrid:_createCell(cx: number, cz: number): Cell
	local config = self.Config
	local rng = seededRandom(cx, cz)
	local cellInfo: Cell = { X = cx, Z = cz, Blades = {} }

	local baseX = cx * config.CellSize
	local baseZ = cz * config.CellSize

	local noiseScale = config.DensityNoiseScale or 0.1
	local noiseThreshold = config.DensityNoiseThreshold or -0.2

	if #self._bladePool < config.BladesPerCell then
		self:_allocateCellBlades()
	end

	local attempts = math.floor(config.BladesPerCell * 1.5)
	local placedCount = 0

	for i = 1, attempts do
		if placedCount >= config.BladesPerCell then break end
		if #self._bladePool == 0 or #self._flowerPool == 0 then self:_allocateCellBlades() end

		local lx = rng:NextNumber(-config.CellSize/2, config.CellSize/2)
		local lz = rng:NextNumber(-config.CellSize/2, config.CellSize/2)
		local x = baseX + lx
		local z = baseZ + lz

		-- Perlin noise for density
		local nx = math.noise(x * noiseScale, z * noiseScale, 0)
		if nx < noiseThreshold then continue end

		local y = config.YOffset

		local rotY = rng:NextNumber(0, math.pi * 2)
		local hScale = rng:NextNumber(0.85, 1.35)
		local isFlower = config.FlowerProbability and rng:NextNumber() < config.FlowerProbability

		local part = isFlower and table.remove(self._flowerPool) or table.remove(self._bladePool)
		if not part then continue end

		if isFlower then
			if config.FlowerColors and #config.FlowerColors > 0 then
				part.Color = config.FlowerColors[rng:NextInteger(1, #config.FlowerColors)]
			end
			hScale = hScale * 0.7
		else
			local hue = rng:NextNumber(config.GrassHueMin, config.GrassHueMax)
			local sat = rng:NextNumber(config.GrassSatMin, config.GrassSatMax)
			local val = rng:NextNumber(config.GrassValMin, config.GrassValMax)
			part.Color = Color3.fromHSV(hue, sat, val)
		end

		local rootY = y - 0.2
		local baseCF = CFrame.new(x, rootY, z) * CFrame.Angles(0, rotY, 0)
		local halfHeight = (config.BladeHeight * hScale * 0.5)
		part.CFrame = baseCF * CFrame.new(0, halfHeight, 0)
		part.Transparency = 0
		local phase = rng:NextNumber(0, 100)

		table.insert(cellInfo.Blades, {
			Part = part,
			BaseCFrame = baseCF,
			Phase = phase,
			HeightScale = hScale,
			WindWaveOffset = x * 0.1 + z * 0.1 + phase * 0.1,
			WindGustOffset = x * 0.05 + z * 0.05,
		})
		placedCount = placedCount + 1
	end

	return cellInfo
end

function GrassGrid:_removeCell(key: string)
	local cell = self._activeCells[key]
	if not cell then return end

	for _, bInfo in ipairs(cell.Blades) do
		bInfo.Part.CFrame = CFrame.new(0, -10000, 0)
		if bInfo.Part.Name == "Flower" then
			table.insert(self._flowerPool, bInfo.Part)
		else
			table.insert(self._bladePool, bInfo.Part)
		end
	end

	self._activeCells[key] = nil
end

function GrassGrid:_updateGrid(playerPos: Vector3)
	local config = self.Config
	local px = playerPos.X
	local pz = playerPos.Z

	local cx = math.floor(px / config.CellSize + 0.5)
	local cz = math.floor(pz / config.CellSize + 0.5)

	if self._lastGridCx == cx and self._lastGridCz == cz then return end
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
		if not needed[k] then self:_removeCell(k) end
	end

	local cellsToCreate = {}
	for k, pos in pairs(needed) do
		if not self._activeCells[k] then
			table.insert(cellsToCreate, {k = k, x = pos.x, z = pos.z})
		end
	end

	-- Sort by distance to spawn closest cells first (avoids progressive popping out of order)
	table.sort(cellsToCreate, function(a, b)
		local distA = (a.x - cx)^2 + (a.z - cz)^2
		local distB = (b.x - cx)^2 + (b.z - cz)^2
		return distA < distB
	end)

	-- Throttle cell creation (max 8 per frame to avoid lag spikes)
	local createdCount = 0
	for _, c in ipairs(cellsToCreate) do
		self._activeCells[c.k] = self:_createCell(c.x, c.z)
		createdCount = createdCount + 1
		if createdCount >= 8 then
			break
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
	local baseWindDir = Vector3.new(math.cos(self._windAngle), 0, math.sin(self._windAngle))
	local timeSec = self._clock
	local config = self.Config

	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or playerPos
	local camLook = camera and camera.CFrame.LookVector or Vector3.new(0,0,-1)

	-- Precomputed constants to reduce per-blade math
	local windStrengthScaled = self._windStrength * 0.1
	local t2 = timeSec * 2
	local t3 = timeSec * 3
	local halfBladeHeight = config.BladeHeight * 0.5
	local px, pz = playerPos.X, playerPos.Z

	for _, cell in pairs(self._activeCells) do
		-- LOD Throttling: Update distant cells less frequently
		local cellCenter = Vector3.new(cell.X * config.CellSize, playerPos.Y, cell.Z * config.CellSize)
		local distToCam = (cellCenter - camPos).Magnitude

		if not cell.LastUpdate then cell.LastUpdate = 0 end
		local updateRate = 0
		if distToCam > config.DrawDistance * 0.6 then
			updateRate = 1 / 10 -- 10 FPS for distant
		elseif distToCam > config.DrawDistance * 0.3 then
			updateRate = 1 / 20 -- 20 FPS for mid
		end

		if timeSec - cell.LastUpdate < updateRate then
			continue
		end
		cell.LastUpdate = timeSec

		-- Frustum Culling (Conservative)
		local toCell = (cellCenter - camPos).Unit
		if distToCam > config.CellSize * 1.5 and camLook:Dot(toCell) < -0.2 then
			continue
		end

		for _, bInfo in ipairs(cell.Blades) do
			-- BOTW Wind (world-space rolling waves + gusts)
			local windWave = math.sin(bInfo.WindWaveOffset + t2)
			local windGust = math.max(0, math.sin(bInfo.WindGustOffset - t3))
			local sway = (windWave * 0.05 + windGust * 0.15) * windStrengthScaled

			-- Player Interaction (Persistent Push Memory)
			local bx, bz = bInfo.BaseCFrame.X, bInfo.BaseCFrame.Z
			local dx, dz = px - bx, pz - bz
			local distToPlayerSq = dx * dx + dz * dz

			if not bInfo.PushTime then bInfo.PushTime = 0 end
			if not bInfo.PushDir then bInfo.PushDir = baseWindDir end

			local pushSway = 0
			local squash = 0
			local currentWindDir = baseWindDir

			if distToPlayerSq < 9.0 then
				bInfo.PushTime = timeSec
				if distToPlayerSq > 0.01 then
					local distToPlayer = math.sqrt(distToPlayerSq)
					bInfo.PushDir = Vector3.new(-dx / distToPlayer, 0, -dz / distToPlayer)
				end
			end

			local timeSincePush = timeSec - bInfo.PushTime
			if timeSincePush < 1.0 then
				local pushIntensity = 1.0 - timeSincePush
				-- Exponential ease out for natural spring back
				pushIntensity = pushIntensity * pushIntensity
				pushSway = pushIntensity * 0.8
				squash = pushIntensity * 0.4
				currentWindDir = baseWindDir:Lerp(bInfo.PushDir, pushIntensity).Unit
			end

			local finalSway = sway + pushSway
			local offset = currentWindDir * (finalSway * config.BladeHeight)
			local rotOffset = CFrame.Angles(finalSway, 0, 0)

			-- Height squash for step-on effect
			local hScale = bInfo.HeightScale * (1.0 - squash)
			bInfo.Part.CFrame = bInfo.BaseCFrame * CFrame.new(0, hScale * halfBladeHeight, 0) * rotOffset + offset
		end
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
