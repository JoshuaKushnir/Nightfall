-- ReplicatedStorage/Modules/Environment/GrassService.lua
-- General-purpose interactive grass for any area (e.g., Heaven surfaces)

local GrassService = {}
GrassService.__index = GrassService

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- ─── Configuration ──────────────────────────────────────────────────────────
local DEFAULT_SETTINGS = {
	POOL_SIZE = 4500,
	RENDER_RADIUS = 130,
	WIND_RADIUS = 70,
	CELL_SIZE = 3.5,
	BLADE_COLOR = Color3.fromRGB(140, 200, 90),
	INTERACTION_RADIUS = 8, -- Distance grass starts parting from player
	HEIGHT = 2,            -- Default base Y if surface is flat at 0
}

export type GrassSurfaceConfig = {
	Id: string?,                    -- Logical name like "HeavenFloor"
	Part: BasePart?,               -- Optional: single part to sample height from
	Height: number?,               -- Optional: fixed Y height (fallback)
	Color: Color3?,                -- Optional: blade color override
	RenderRadius: number?,         -- Optional override
	WindRadius: number?,
	InteractionRadius: number?,
	CellSize: number?,
}

-- Instance represents one logical patch system (e.g. one map/realm)
function GrassService.new(settings: { [string]: any }?)
	local merged = table.clone(DEFAULT_SETTINGS)
	if settings then
		for k, v in pairs(settings) do
			merged[k] = v
		end
	end

	local self = setmetatable({}, GrassService)

	self.Settings = merged
	self.Pool = {}
	self.Active = {}
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "Grass_Render"
	self.Folder.Parent = Workspace

	self._lastGridPos = nil
	self._connection = nil
	self._player: Player? = nil

	-- Surfaces this instance is allowed to render over
	self.Surfaces = {} :: { GrassSurfaceConfig }

	self:_setupPool()
	return self
end

-- Register a surface this GrassService can render on.
-- Example:
-- Grass:RegisterSurface({
--   Id = "HeavenFloor",
--   Part = Workspace.HeavenFloor,
--   Color = Color3.fromRGB(170, 220, 120),
-- })
function GrassService:RegisterSurface(config: GrassSurfaceConfig)
	table.insert(self.Surfaces, config)
end

-- Convenience to clear registered surfaces (e.g., when changing realms)
function GrassService:ClearSurfaces()
	table.clear(self.Surfaces)
end

function GrassService:_setupPool()
	local template = Instance.new("WedgePart")
	template.Size = Vector3.new(0.15, 4, 0.4)
	template.Anchored = true
	template.CanCollide = false
	template.CastShadow = false
	template.Material = Enum.Material.SmoothPlastic
	template.Color = self.Settings.BLADE_COLOR

	for i = 1, self.Settings.POOL_SIZE do
		local clone = template:Clone()
		clone.CFrame = CFrame.new(0, -500, 0)
		clone.Parent = self.Folder
		table.insert(self.Pool, clone)
	end
	template:Destroy()
end

-- Deterministic per-cell randomization
function GrassService:_getCellData(x: number, z: number)
	local seed = (x * 73856093) % 19349663 + (z * 83492791) % 23459113
	local rng = Random.new(seed)
	return rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(0.7, 1.3), rng:NextNumber(0, math.pi * 2)
end

-- Sample height at a world position based on registered surfaces.
-- If a Part is provided, we raycast down from above; otherwise fall back to fixed Height.
function GrassService:_getHeightAt(worldPos: Vector3): (number?, GrassSurfaceConfig?)
	if #self.Surfaces == 0 then
		return self.Settings.HEIGHT, nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include

	local includeParts = {}
	for _, surface in ipairs(self.Surfaces) do
		if surface.Part then
			table.insert(includeParts, surface.Part)
		end
	end

	if #includeParts == 0 then
		-- No parts configured: just use first surface with Height, else default
		local surf = self.Surfaces[1]
		local y = surf.Height or self.Settings.HEIGHT
		return y, surf
	end

	params.FilterDescendantsInstances = includeParts

	local origin = worldPos + Vector3.new(0, 50, 0)
	local direction = Vector3.new(0, -200, 0)

	local result = Workspace:Raycast(origin, direction, params)
	if result and result.Instance then
		-- Find the matching surface
		local hitPart = result.Instance
		for _, surface in ipairs(self.Surfaces) do
			if surface.Part == hitPart then
				return result.Position.Y, surface
			end
		end
		-- Hit a registered part but didn't match by reference; still use Y
		return result.Position.Y, nil
	end

	-- Fallback: use the first surface's fixed height if provided
	local fallbackSurface = self.Surfaces[1]
	local fallbackY = fallbackSurface.Height or self.Settings.HEIGHT
	return fallbackY, fallbackSurface
end

function GrassService:_updateGrid(centerPos: Vector3)
	local cellSize = self.Settings.CELL_SIZE
	local gX = math.floor(centerPos.X / cellSize) * cellSize
	local gZ = math.floor(centerPos.Z / cellSize) * cellSize
	local currentPos = Vector3.new(gX, 0, gZ)

	if self._lastGridPos and (self._lastGridPos - currentPos).Magnitude < cellSize then
		return
	end
	self._lastGridPos = currentPos

	-- Recycle previous blades
	for _, data in ipairs(self.Active) do
		local part = data.Part
		table.insert(self.Pool, part)
		part.CFrame = CFrame.new(0, -500, 0)
	end
	table.clear(self.Active)

	local extent = math.floor(self.Settings.RENDER_RADIUS / cellSize)
	for x = -extent, extent do
		for z = -extent, extent do
			if x * x + z * z > extent * extent then
				continue
			end
			if #self.Pool == 0 then
				break
			end

			local wX = gX + (x * cellSize)
			local wZ = gZ + (z * cellSize)

			local heightY, surface = self:_getHeightAt(Vector3.new(wX, 0, wZ))
			if not heightY then
				continue
			end

			local offX, offZ, _hMult, rotY = self:_getCellData(wX, wZ)
			local pos = Vector3.new(wX + offX, heightY, wZ + offZ)
			local baseCF = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)

			local blade = table.remove(self.Pool)

			-- Color override per-surface
			if surface and surface.Color then
				blade.Color = surface.Color
			else
				blade.Color = self.Settings.BLADE_COLOR
			end

			table.insert(self.Active, {
				Part = blade,
				BaseCF = baseCF,
				Pos = pos,
			})
		end
	end
end

-- Start following a player and rendering grass around them
function GrassService:Start(player: Player)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end

	self._player = player

	self._connection = RunService.RenderStepped:Connect(function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local rootPos = root.Position
		self:_updateGrid(rootPos)

		local t = tick()
		local windRadius = self.Settings.WIND_RADIUS
		local interactRadius = self.Settings.INTERACTION_RADIUS

		for _, data in ipairs(self.Active) do
			local dist = (rootPos - data.Pos).Magnitude

			if dist < windRadius then
				-- Wind sway
				local noise = math.noise(data.Pos.X * 0.1, t * 0.5, data.Pos.Z * 0.1)
				local windAngle = math.rad(noise * 25)

				-- Interaction (parting the grass near the player)
				local interactionCF = CFrame.identity
				if dist < interactRadius then
					local diff = (data.Pos - rootPos).Unit
					local strength = 1 - (dist / interactRadius)
					interactionCF = CFrame.Angles(diff.X * strength, 0, diff.Z * strength)
				end

				data.Part.CFrame = data.BaseCF * interactionCF * CFrame.Angles(windAngle, 0, windAngle)
			else
				data.Part.CFrame = data.BaseCF
			end
		end
	end)
end

function GrassService:Stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self._player = nil

	-- Return everything to pool position
	for _, data in ipairs(self.Active) do
		local part = data.Part
		table.insert(self.Pool, part)
		part.CFrame = CFrame.new(0, -500, 0)
	end
	table.clear(self.Active)

	self.Folder:ClearAllChildren()
end

return GrassService
