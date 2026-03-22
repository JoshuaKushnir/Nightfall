-- ReplicatedStorage/Modules/Environment/GrassService.lua
local GrassService = {}
GrassService.__index = GrassService

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- ─── Configuration ──────────────────────────────────────────────────────────
local SETTINGS = {
	POOL_SIZE = 4500,
	RENDER_RADIUS = 130,
	WIND_RADIUS = 70,
	CELL_SIZE = 3.5,
	BLADE_COLOR = Color3.fromRGB(140, 200, 90),
	INTERACTION_RADIUS = 8, -- Distance grass starts parting from player
}

function GrassService.new(height: number)
	local self = setmetatable({}, GrassService)
	
	self.Height = height
	self.Pool = {}
	self.Active = {}
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "EtherealGrass_Render"
	self.Folder.Parent = Workspace
	
	self._lastGridPos = nil
	self._connection = nil
	
	self:SetupPool()
	return self
end

function GrassService:SetupPool()
	local template = Instance.new("WedgePart")
	template.Size = Vector3.new(0.15, 4, 0.4)
	template.Anchored = true
	template.CanCollide = false
	template.CastShadow = false
	template.Material = Enum.Material.SmoothPlastic
	template.Color = SETTINGS.BLADE_COLOR
	
	for i = 1, SETTINGS.POOL_SIZE do
		local clone = template:Clone()
		clone.CFrame = CFrame.new(0, -500, 0)
		clone.Parent = self.Folder
		table.insert(self.Pool, clone)
	end
	template:Destroy()
end

function GrassService:GetCellData(x, z)
	local seed = (x * 73856093) % 19349663 + (z * 83492791) % 23459113
	local rng = Random.new(seed)
	return rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(0.7, 1.3), rng:NextNumber(0, math.pi * 2)
end

function GrassService:UpdateGrid(centerPos)
	local gX = math.floor(centerPos.X / SETTINGS.CELL_SIZE) * SETTINGS.CELL_SIZE
	local gZ = math.floor(centerPos.Z / SETTINGS.CELL_SIZE) * SETTINGS.CELL_SIZE
	local currentPos = Vector3.new(gX, 0, gZ)
	
	if self._lastGridPos and (self._lastGridPos - currentPos).Magnitude < SETTINGS.CELL_SIZE then return end
	self._lastGridPos = currentPos
	
	-- Recycle
	for _, data in ipairs(self.Active) do
		table.insert(self.Pool, data.Part)
		data.Part.CFrame = CFrame.new(0, -500, 0)
	end
	table.clear(self.Active)
	
	local extent = math.floor(SETTINGS.RENDER_RADIUS / SETTINGS.CELL_SIZE)
	for x = -extent, extent do
		for z = -extent, extent do
			if x*x + z*z > extent*extent then continue end
			if #self.Pool == 0 then break end
			
			local wX, wZ = gX + (x * SETTINGS.CELL_SIZE), gZ + (z * SETTINGS.CELL_SIZE)
			local offX, offZ, hMult, rotY = self:GetCellData(wX, wZ)
			
			local baseCF = CFrame.new(wX + offX, self.Height, wZ + offZ) * CFrame.Angles(0, rotY, 0)
			local blade = table.remove(self.Pool)
			
			table.insert(self.Active, {
				Part = blade,
				BaseCF = baseCF,
				Pos = Vector3.new(wX + offX, self.Height, wZ + offZ)
			})
		end
	end
end

function GrassService:Start(playerObj)
	self._connection = RunService.RenderStepped:Connect(function()
		local char = playerObj.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end
		local rootPos = char.HumanoidRootPart.Position
		
		self:UpdateGrid(rootPos)
		
		local t = tick()
		for _, data in ipairs(self.Active) do
			local dist = (rootPos - data.Pos).Magnitude
			
			if dist < SETTINGS.WIND_RADIUS then
				-- Wind Sway
				local noise = math.noise(data.Pos.X * 0.1, t * 0.5, data.Pos.Z * 0.1)
				local windAngle = math.rad(noise * 25)
				
				-- Interaction (Parting the grass)
				local interactionCF = CFrame.identity
				if dist < SETTINGS.INTERACTION_RADIUS then
					local diff = (data.Pos - rootPos).Unit
					local strength = 1 - (dist / SETTINGS.INTERACTION_RADIUS)
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
	if self._connection then self._connection:Disconnect() end
	self.Folder:ClearAllChildren()
end

return GrassService