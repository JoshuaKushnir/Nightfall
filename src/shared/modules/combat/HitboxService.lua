--!strict
--[[
	HitboxService.lua

	Issue #7: Modular Raycast-Based Hitbox System
	Epic: Phase 2 - Combat & Fluidity

	Server-authoritative hitbox detection system. Supports Box, Sphere, and Raycast shapes.
	Client predicts hits; server validates and confirms damage.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxTypes = require(ReplicatedStorage.Shared.types.HitboxTypes)
local StateService = require(ReplicatedStorage.Shared.modules.core.StateService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local Utils = require(ReplicatedStorage.Shared.modules.core.Utils)
local DebugSettings = require(ReplicatedStorage.Shared.modules.core.DebugSettings)

type Hitbox = HitboxTypes.Hitbox
type HitboxConfig = HitboxTypes.HitboxConfig
type HitData = HitboxTypes.HitData

local HitboxService = {}

-- Storage
local ActiveHitboxes: {Hitbox} = {}
local HitboxCounter = 0
local HitboxVisuals: {[Hitbox]: Instance?} = {} -- Debug visualization objects

-- Constants
local HITBOX_UPDATE_RATE = 0.016 -- 60 FPS
local SPATIAL_PARTITION_SIZE = 50 -- studs per partition

--[[
	Create a new hitbox
	@param config The hitbox configuration
	@return The created hitbox
]]
function HitboxService.CreateHitbox(config: HitboxConfig): Hitbox
	assert(config, "Config cannot be nil")
	assert(config.Owner, "Config.Owner cannot be nil")
	assert(config.Shape, "Config.Shape cannot be nil")

	print(`[HitboxService] CreateHitbox called with shape {config.Shape}`)

	HitboxCounter += 1

	local hitbox: Hitbox = {
		Id = `HB_{HitboxCounter}_{os.clock()}`,
		Config = config,
		Active = true,
		CreatedTime = tick(),
		HitTargets = {},

		Hit = function(self: Hitbox, target: any): boolean
			if not self:IsValidTarget(target) then
				return false
			end

			table.insert(self.HitTargets, target)

			local hitData: HitData = {
				Hitbox = self,
				Target = target,
				Position = self.Config.Position or self.Config.Origin or Vector3.new(0, 0, 0),
				HitTime = tick(),
				Damage = self.Config.Damage,
			}

			if self.Config.OnHit then
				task.spawn(self.Config.OnHit, target, hitData)
			end

			local targetName = typeof(target) == "Instance" and target.Name or tostring(target)
			print(`[HitboxService] Hit confirmed: {self.Id} -> {targetName} ({self.Config.Damage} damage)`)
			return true
		end,

		Update = function(self: Hitbox, position: Vector3?)
			if position then
				self.Config.Position = position
				if self.Config.Shape == "Raycast" then
					self.Config.Origin = position
				end
				-- Update debug visual
				HitboxService._UpdateVisual(self)
			end
		end,

		Expire = function(self: Hitbox)
			self.Active = false
			table.remove(ActiveHitboxes, table.find(ActiveHitboxes, self) or -1)

			-- Remove debug visual
			HitboxService._RemoveVisual(self)

			if self.Config.OnExpire then
				task.spawn(self.Config.OnExpire)
			end

			print(`[HitboxService] Hitbox expired: {self.Id}`)
		end,

		IsValidTarget = function(self: Hitbox, target: any): boolean
			-- Already hit
			if table.find(self.HitTargets, target) and not self.Config.CanHitTwice then
				return false
			end

			-- Owner can't hit self
			if self.Config.Owner == target then
				return false
			end

			-- Blacklist check
			if self.Config.Blacklist and table.find(self.Config.Blacklist, target) then
				return false
			end

			-- State validation (only for players)
			if self.Config.StunAffinity and typeof(target) == "Instance" and target:IsA("Player") then
				local targetData = StateService:GetPlayerData(target)
				if not targetData or not table.find(self.Config.StunAffinity, targetData.State) then
					return false
				end
			end

			-- Target must exist
			if typeof(target) == "Instance" and not target.Parent then
				return false
			end

			return true
		end,

		CheckShape = function(self: Hitbox, targetPosition: Vector3): boolean
			-- Deprecated in favor of native Roblox spatial queries in TestHitbox
			-- Keeping for backward compatibility or simple distance tests
			local shape = self.Config.Shape

			if shape == "Sphere" then
				if not self.Config.Position or not self.Config.Size then return false end
				local radius = self.Config.Size.X
				return Utils.PointInSphere(targetPosition, self.Config.Position, radius)
			elseif shape == "Box" or shape == "Square" then
				if not self.Config.Position or not self.Config.Size then return false end
				local cf = self.Config.CFrame or CFrame.new(self.Config.Position)
				local localPos = cf:PointToObjectSpace(targetPosition)
				local size = shape == "Square" and Vector3.new(self.Config.Size.X, 0.5, self.Config.Size.Z or self.Config.Size.X) or self.Config.Size
				local halfSize = size / 2
				return math.abs(localPos.X) <= halfSize.X and math.abs(localPos.Y) <= halfSize.Y and math.abs(localPos.Z) <= halfSize.Z
			elseif shape == "Cylinder" or shape == "Circle" then
				if not self.Config.Position then return false end
				local radius = self.Config.Radius or (self.Config.Size and self.Config.Size.X) or 5
				local height = shape == "Circle" and 0.5 or (self.Config.Size and self.Config.Size.Y) or 10
				local cf = self.Config.CFrame or CFrame.new(self.Config.Position)
				local localPos = cf:PointToObjectSpace(targetPosition)
				return math.abs(localPos.Y) <= height/2 and math.sqrt(localPos.X^2 + localPos.Z^2) <= radius
			elseif shape == "Cone" then
				if not self.Config.Origin or not self.Config.Direction or not self.Config.Length then return false end
				local toTarget = targetPosition - self.Config.Origin
				local fwdDist = toTarget:Dot(self.Config.Direction.Unit)
				if fwdDist < 0 or fwdDist > self.Config.Length then return false end

				local baseWidth = self.Config.Width or (self.Config.Radius and self.Config.Radius * 2) or (math.tan(math.rad(self.Config.Angle or 45)) * self.Config.Length * 2)
				local baseHeight = self.Config.Height or (self.Config.Radius and self.Config.Radius * 2) or baseWidth

				local cf = CFrame.lookAt(self.Config.Origin, self.Config.Origin + self.Config.Direction.Unit)
				local projLocal = cf:VectorToObjectSpace(toTarget - self.Config.Direction.Unit * fwdDist)
				local maxW = (fwdDist / self.Config.Length) * (baseWidth / 2)
				local maxH = (fwdDist / self.Config.Length) * (baseHeight / 2)

				if maxW > 0 and maxH > 0 then
					return (projLocal.X^2 / maxW^2) + (projLocal.Y^2 / maxH^2) <= 1
				end
				return false
			elseif shape == "Raycast" then
				if not self.Config.Origin or not self.Config.Direction or not self.Config.Length then return false end
				local _, distance = Utils.ClosestPointOnRay(self.Config.Origin, self.Config.Direction, self.Config.Length, targetPosition)
				return distance <= 3
			end
			return false
		end,
	}

	table.insert(ActiveHitboxes, hitbox)

	-- Create debug visual (always create, will be shown/hidden based on setting)
	HitboxService._CreateVisual(hitbox)
	-- Ensure hitboxes expire: prefer explicit LifeTime, fall back to Duration, otherwise use a safe default
	local life = config.LifeTime or config.Duration or 0.5
	task.delay(life, function()
		if hitbox.Active then
			hitbox:Expire()
		end
	end)

	local ownerName = type(config.Owner) == "string" and config.Owner or (typeof(config.Owner) == "Instance" and config.Owner.Name or "Unknown")
	print(`[HitboxService] Created hitbox: {hitbox.Id} ({config.Shape}, Owner: {ownerName})`)
	return hitbox
end

--[[
	Get all active hitboxes for a player
	@param player The player to check
	@return Array of hitboxes owned by the player
]]
function HitboxService.GetPlayerHitboxes(player: Player): {Hitbox}
	local playerHitboxes: {Hitbox} = {}

	for _, hitbox in ActiveHitboxes do
		if hitbox.Config.Owner == player and hitbox.Active then
			table.insert(playerHitboxes, hitbox)
		end
	end

	return playerHitboxes
end

--[[
	Test hitbox against the world using spatial queries and process hits
	@param hitbox The hitbox to test
	@return Number of targets hit
]]
function HitboxService.TestHitbox(hitbox: Hitbox): number
	if not hitbox.Active then
		return 0
	end

	local hitCount = 0
	local config = hitbox.Config
	local shape = config.Shape

	-- Setup OverlapParams for performant spatial queries
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Exclude the owner's character
	local ownerChar = typeof(config.Owner) == "Instance" and config.Owner:IsA("Player") and config.Owner.Character
	if ownerChar then
		params.FilterDescendantsInstances = {ownerChar}
	end

	-- We only care about characters or dummies, usually stored in workspace, but let's query everything
	local results: {BasePart} = {}

	if shape == "Sphere" then
		if not config.Position or not config.Size then return 0 end
		local radius = config.Size.X
		results = workspace:GetPartBoundsInRadius(config.Position, radius, params)

	elseif shape == "Box" or shape == "Square" then
		if not config.Position or not config.Size then return 0 end
		-- Use CFrame if provided, else construct from Position
		local cf = config.CFrame or CFrame.new(config.Position)
		local size = shape == "Square" and Vector3.new(config.Size.X, 0.5, config.Size.Z or config.Size.X) or config.Size
		results = workspace:GetPartBoundsInBox(cf, size, params)

	elseif shape == "Cylinder" or shape == "Circle" then
		if not config.Position then return 0 end
		local radius = config.Radius or (config.Size and config.Size.X) or 5
		local height = shape == "Circle" and 0.5 or (config.Size and config.Size.Y) or 10
		local cf = config.CFrame or CFrame.new(config.Position)
		local boxSize = Vector3.new(radius * 2, height, radius * 2)
		local potentialResults = workspace:GetPartBoundsInBox(cf, boxSize, params)

		for _, part in ipairs(potentialResults) do
			-- Basic filtering for cylinder shape
			local localPos = cf:PointToObjectSpace(part.Position)
			local dist = math.sqrt(localPos.X^2 + localPos.Z^2)
			-- Add part size into consideration roughly
			if dist <= radius + (part.Size.Magnitude / 2) then
				table.insert(results, part)
			end
		end

	elseif shape == "Cone" then
		if not config.Origin or not config.Direction or not config.Length then return 0 end
		local length = config.Length
		local baseWidth = config.Width or (config.Radius and config.Radius * 2) or (math.tan(math.rad(config.Angle or 45)) * length * 2)
		local baseHeight = config.Height or (config.Radius and config.Radius * 2) or baseWidth
		local fwd = config.Direction.Unit

		local cf = CFrame.lookAt(config.Origin, config.Origin + fwd)
		local centerCf = cf * CFrame.new(0, 0, -length/2)
		local boxSize = Vector3.new(baseWidth, baseHeight, length)
		local potentialResults = workspace:GetPartBoundsInBox(centerCf, boxSize, params)

		for _, part in ipairs(potentialResults) do
			local toPart = part.Position - config.Origin
			local fwdDist = toPart:Dot(fwd)
			if fwdDist > 0 and fwdDist <= length then
				local proj = toPart - fwd * fwdDist
				local projLocal = cf:VectorToObjectSpace(proj)

				local maxW = (fwdDist / length) * (baseWidth / 2)
				local maxH = (fwdDist / length) * (baseHeight / 2)

				-- Ellipsoid logic
				local rX = maxW + (part.Size.Magnitude / 2)
				local rY = maxH + (part.Size.Magnitude / 2)

				if rX > 0 and rY > 0 then
					local val = (projLocal.X^2 / rX^2) + (projLocal.Y^2 / rY^2)
					if val <= 1 then
						table.insert(results, part)
					end
				end
			end
		end

	elseif shape == "Raycast" then
		if not config.Origin or not config.Direction or not config.Length then return 0 end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		if ownerChar then
			rayParams.FilterDescendantsInstances = {ownerChar}
		end

		-- Use Blockcast for a 'thick' ray (3x3 default, could parameterise later)
		local castSize = Vector3.new(3, 3, 0.1)
		local castDir = config.Direction.Unit * config.Length

		-- LookAt CFrame so the Z axis aligns with direction
		local startCF = CFrame.lookAt(config.Origin, config.Origin + config.Direction)

		local blockCastResult = workspace:Blockcast(startCF, castSize, castDir, rayParams)
		if blockCastResult and blockCastResult.Instance then
			table.insert(results, blockCastResult.Instance)
		end
	end

	-- Process hit parts to find valid characters/dummies
	local processedModels = {}
	for _, part in ipairs(results) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or processedModels[model] then continue end

		-- Ensure it's a character, dummy, or hollowed
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then continue end

		-- Extract target identifier
		local target: any = nil
		local player = Players:GetPlayerFromCharacter(model)

		if player then
			target = player
		elseif model.Name:match("^Dummy_") then
			target = model.Name:match("^Dummy_(.*)")
		elseif model.Name:match("^Hollowed_") then
			target = model.Name
		end

		if target then
			-- Mark model as processed to avoid multiple hits per cast
			processedModels[model] = true

			if hitbox:IsValidTarget(target) then
				if hitbox:Hit(target) then
					hitCount += 1
				end
			end
		end
	end

	return hitCount
end

--[[
	Remove a hitbox
	@param hitbox The hitbox to remove
]]
function HitboxService.RemoveHitbox(hitbox: Hitbox)
	if hitbox.Active then
		hitbox:Expire()
	end
end

--[[
	Clear all hitboxes (shutdown)
]]
function HitboxService.Clear()
	while #ActiveHitboxes > 0 do
		table.remove(ActiveHitboxes, 1):Expire()
	end
	print("[HitboxService] All hitboxes cleared")
end

--[[
	Create debug visualization for a hitbox
	@param hitbox The hitbox to visualize
]]
function HitboxService._CreateVisual(hitbox: Hitbox)
	print(`[HitboxService] _CreateVisual called for {hitbox.Id}`)

	local config = hitbox.Config
	local visual: Instance?

	-- Create folder for all visuals
	if not HitboxService._VisualFolder then
		print(`[HitboxService] Creating visual folder in workspace`)
		HitboxService._VisualFolder = Instance.new("Folder")
		HitboxService._VisualFolder.Name = "HitboxVisuals"
		HitboxService._VisualFolder.Parent = workspace
		print(`[HitboxService] Visual folder created and parented to workspace`)
	end

	if config.Shape == "Sphere" then
		print(`[HitboxService] Creating sphere visual`)
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = (config.Size or Vector3.new(1, 1, 1)) * 2
		part.Position = config.Position or Vector3.new(0, 0, 0)
		part.CanCollide = false
		part.Anchored = true
		part.CanQuery = false
		part.Massless = true
		part.CFrame = CFrame.new(config.Position or Vector3.new(0, 0, 0))
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(0, 255, 0) -- Green
		part.Transparency = 0.7
		part.Name = `Hitbox_{hitbox.Id}`
		part.Parent = HitboxService._VisualFolder
		visual = part
		print(`[HitboxService] Sphere visual created at {part.Position}`)

	elseif config.Shape == "Box" or config.Shape == "Square" then
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = config.Shape == "Square" and Vector3.new((config.Size and config.Size.X) or 1, 0.5, (config.Size and (config.Size.Z or config.Size.X)) or 1) or (config.Size or Vector3.new(1, 1, 1))
		part.Position = config.Position or Vector3.new(0, 0, 0)
		part.CanCollide = false
		part.Anchored = true
		part.CanQuery = false
		part.Massless = true
		part.CFrame = config.CFrame or CFrame.new(config.Position or Vector3.new(0, 0, 0))
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(0, 0, 255) -- Blue
		part.Transparency = 0.7
		part.Name = `Hitbox_{hitbox.Id}`
		part.Parent = HitboxService._VisualFolder
		visual = part

	elseif config.Shape == "Cylinder" or config.Shape == "Circle" then
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		local r = config.Radius or (config.Size and config.Size.X) or 5
		local h = config.Shape == "Circle" and 0.5 or (config.Size and config.Size.Y) or 10
		-- Cylinder shape in Roblox uses X for height, Y/Z for diameter
		part.Size = Vector3.new(h, r * 2, r * 2)
		part.CanCollide = false
		part.Anchored = true
		part.CanQuery = false
		part.Massless = true

		local baseCf = config.CFrame or CFrame.new(config.Position or Vector3.new(0, 0, 0))
		-- Orient so it stands up like a typical cylinder/circle instead of on its side
		part.CFrame = baseCf * CFrame.Angles(0, 0, math.pi/2)

		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 165, 0) -- Orange
		part.Transparency = 0.7
		part.Name = `Hitbox_{hitbox.Id}`
		part.Parent = HitboxService._VisualFolder
		visual = part

	elseif config.Shape == "Cone" then
		-- Visualize cone using a WedgePart or Cone mesh
		local part = Instance.new("Part")
		-- We use a SpecialMesh for Cone
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = part

		-- Just making it a Wedge part to roughly show the area or we can just use a generic part
		local length = config.Length or 10
		local baseWidth = config.Width or (config.Radius and config.Radius * 2) or (math.tan(math.rad(config.Angle or 45)) * length * 2)
		local baseHeight = config.Height or (config.Radius and config.Radius * 2) or baseWidth

		part.Size = Vector3.new(baseWidth, baseHeight, length)
		part.CanCollide = false
		part.Anchored = true
		part.CanQuery = false
		part.Massless = true

		if config.Origin and config.Direction then
			local fwd = config.Direction.Unit
			local cf = CFrame.lookAt(config.Origin, config.Origin + fwd)
			-- center of visual
			part.CFrame = cf * CFrame.new(0, 0, -length/2)
		end

		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 0, 255) -- Magenta
		part.Transparency = 0.7
		part.Name = `Hitbox_{hitbox.Id}`
		part.Parent = HitboxService._VisualFolder
		visual = part

	elseif config.Shape == "Raycast" then
		-- Create a thin cylinder for raycast visualization
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.3, config.Length or 10, 0.3)
		part.CanCollide = false
		part.Anchored = true
		part.CanQuery = false
		part.Massless = true
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 0, 0) -- Red
		part.Transparency = 0.7
		part.Name = `Hitbox_{hitbox.Id}`

		-- Position along ray
		if config.Origin and config.Direction then
			local rayMidpoint = config.Origin + (config.Direction.Unit * (config.Length or 10) / 2)
			part.CFrame = CFrame.new(rayMidpoint, rayMidpoint + config.Direction)
		end

		part.Parent = HitboxService._VisualFolder
		visual = part
	end

	HitboxVisuals[hitbox] = visual
	HitboxService._UpdateVisualVisibility()
end

--[[
	Update debug visualization for a hitbox
	@param hitbox The hitbox to update
]]
function HitboxService._UpdateVisual(hitbox: Hitbox)
	local visual = HitboxVisuals[hitbox]
	if not visual then
		return
	end

	local config = hitbox.Config

	if config.Shape == "Sphere" or config.Shape == "Box" or config.Shape == "Square" then
		if config.Position then
			visual.CFrame = config.CFrame or CFrame.new(config.Position)
		end
	elseif config.Shape == "Cylinder" or config.Shape == "Circle" then
		if config.Position then
			local baseCf = config.CFrame or CFrame.new(config.Position)
			visual.CFrame = baseCf * CFrame.Angles(0, 0, math.pi/2)
		end
	elseif config.Shape == "Cone" then
		if config.Origin and config.Direction and config.Length then
			local fwd = config.Direction.Unit
			local cf = CFrame.lookAt(config.Origin, config.Origin + fwd)
			visual.CFrame = cf * CFrame.new(0, 0, -config.Length/2)
		end
	elseif config.Shape == "Raycast" then
		if config.Origin and config.Direction then
			local rayMidpoint = config.Origin + (config.Direction.Unit * (config.Length or 10) / 2)
			visual.CFrame = CFrame.new(rayMidpoint, rayMidpoint + config.Direction)
		end
	end
end

--[[
	Remove debug visualization for a hitbox
	@param hitbox The hitbox to stop displaying
]]
function HitboxService._RemoveVisual(hitbox: Hitbox)
	local visual = HitboxVisuals[hitbox]
	if visual then
		visual:Destroy()
		HitboxVisuals[hitbox] = nil
	end
end

--[[
	Update visibility of all hitbox visuals based on ShowHitboxes setting
]]
function HitboxService._UpdateVisualVisibility()
	if not HitboxService._VisualFolder then
		HitboxService._VisualFolder = workspace:FindFirstChild("HitboxVisuals") or ReplicatedStorage:FindFirstChild("HitboxVisuals")
	end

	if not HitboxService._VisualFolder then return end

	local showHitboxes = DebugSettings.Get("ShowHitboxes")

	-- If on client, reparenting the folder to ReplicatedStorage or Camera instead of nil
	-- prevents constant server replication from bringing pieces back when the folder syncs
	if showHitboxes then
		HitboxService._VisualFolder.Parent = workspace
	else
		-- Hide all visuals. If client, move to CurrentCamera so it disappears without destroying server sync
		local RunService = game:GetService("RunService")
		if RunService:IsClient() then
			HitboxService._VisualFolder.Parent = workspace.CurrentCamera
		else
			HitboxService._VisualFolder.Parent = ReplicatedStorage
		end
	end
end

--[[
	Toggle all hitbox visuals on/off (legacy, now handled by _UpdateVisualVisibility)
	@param enabled Whether to show hitboxes
]]
function HitboxService._SetVisualsEnabled(enabled: boolean)
	HitboxService._UpdateVisualVisibility()
end

-- Setup debug setting listener
DebugSettings.OnChanged("ShowHitboxes", function(_, enabled)
	HitboxService._UpdateVisualVisibility()
end)

-- Auto-test all active hitboxes every frame
RunService.Heartbeat:Connect(function()
	-- Iterate a snapshot so Expire() mutations don't break the loop
	local snapshot = table.clone(ActiveHitboxes)
	for _, hitbox in snapshot do
		if hitbox.Active then
			HitboxService.TestHitbox(hitbox)
		end
	end
end)

return HitboxService
