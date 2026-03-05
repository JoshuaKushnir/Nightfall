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
local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)

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

		Hit = function(self: Hitbox, target: Player): boolean
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

			print(`[HitboxService] Hit confirmed: {self.Id} -> {target.Name} ({self.Config.Damage} damage)`)
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
			elseif shape == "Box" then
				if not self.Config.Position or not self.Config.Size then return false end
				local cf = self.Config.CFrame or CFrame.new(self.Config.Position)
				local localPos = cf:PointToObjectSpace(targetPosition)
				local halfSize = self.Config.Size / 2
				return math.abs(localPos.X) <= halfSize.X and math.abs(localPos.Y) <= halfSize.Y and math.abs(localPos.Z) <= halfSize.Z
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
	if config.LifeTime then
		task.delay(config.LifeTime, function()
			if hitbox.Active then
				hitbox:Expire()
			end
		end)
	end

	print(`[HitboxService] Created hitbox: {hitbox.Id} ({config.Shape}, Owner: {config.Owner.Name})`)
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

	elseif shape == "Box" then
		if not config.Position or not config.Size then return 0 end
		-- Use CFrame if provided, else construct from Position
		local cf = config.CFrame or CFrame.new(config.Position)
		results = workspace:GetPartBoundsInBox(cf, config.Size, params)

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

		-- Ensure it's a character or dummy
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then continue end

		-- Extract target identifier
		local target: any = nil
		local player = Players:GetPlayerFromCharacter(model)
		
		if player then
			target = player
		elseif model.Name:match("^Dummy_") then
			target = model.Name:match("^Dummy_(.*)")
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

	elseif config.Shape == "Box" then
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = config.Size or Vector3.new(1, 1, 1)
		part.Position = config.Position or Vector3.new(0, 0, 0)
		part.CanCollide = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(0, 0, 255) -- Blue
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

	if config.Shape == "Sphere" or config.Shape == "Box" then
		if config.Position then
			visual.Position = config.Position
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
		return
	end

	local showHitboxes = DebugSettings.Get("ShowHitboxes")

	if showHitboxes then
		-- Show all visuals
		HitboxService._VisualFolder.Parent = workspace
	else
		-- Hide all visuals by removing folder from workspace
		HitboxService._VisualFolder.Parent = nil
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

-- Auto-test all active hitboxes every frame (client-side hit detection)
if RunService:IsClient() then
	RunService.Heartbeat:Connect(function()
		-- Iterate a snapshot so Expire() mutations don't break the loop
		local snapshot = table.clone(ActiveHitboxes)
		for _, hitbox in snapshot do
			if hitbox.Active then
				HitboxService.TestHitbox(hitbox)
			end
		end
	end)
end

return HitboxService
