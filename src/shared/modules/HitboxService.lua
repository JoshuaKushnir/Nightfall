--!strict
--[[
	HitboxService.lua
	
	Issue #7: Modular Raycast-Based Hitbox System
	Epic: Phase 2 - Combat & Fluidity
	
	Server-authoritative hitbox detection system. Supports Box, Sphere, and Raycast shapes.
	Client predicts hits; server validates and confirms damage.
]]

local Players = game:GetService("Players")
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
			local shape = self.Config.Shape
			
			if shape == "Sphere" then
				if not self.Config.Position or not self.Config.Size then
					return false
				end
				
				local radius = self.Config.Size.X
				return Utils.PointInSphere(targetPosition, self.Config.Position, radius)
				
			elseif shape == "Box" then
				if not self.Config.Position or not self.Config.Size then
					return false
				end
				
				return Utils.PointInBox(targetPosition, self.Config.Position, self.Config.Size)
				
			elseif shape == "Raycast" then
				if not self.Config.Origin or not self.Config.Direction or not self.Config.Length then
					return false
				end
				
				local _, distance = Utils.ClosestPointOnRay(self.Config.Origin, self.Config.Direction, self.Config.Length, targetPosition)
				return distance <= 3 -- 3 stud radius for raycast
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
	Test hitbox against all players and process hits
	@param hitbox The hitbox to test
	@return Number of targets hit
]]
function HitboxService.TestHitbox(hitbox: Hitbox): number
	if not hitbox.Active then
		return 0
	end
	
	local hitCount = 0
	
	-- Test against players
	for _, player in Players:GetPlayers() do
		if player == hitbox.Config.Owner then
			continue
		end
		
		if not hitbox:IsValidTarget(player) then
			continue
		end
		
		-- Get target position using Utils
		local humanoidRootPart = Utils.GetRootPart(player)
		if not humanoidRootPart then
			continue
		end
		
		-- Check shape collision
		if hitbox:CheckShape(humanoidRootPart.Position) then
			if hitbox:Hit(player) then
				hitCount += 1
			end
		end
	end
	
	-- Test against dummies
	for _, model in Workspace:GetChildren() do
		if model:IsA("Model") and model.Name:match("^Dummy_") then
			local dummyId = model.Name:match("^Dummy_(.*)")
			if not dummyId then
				continue
			end
			
			if not hitbox:IsValidTarget(model) then
				continue
			end
			
			-- Get position from Body part
			local bodyPart = model:FindFirstChild("Body")
			if not bodyPart then
				continue
			end
			
			-- Check shape collision
			if hitbox:CheckShape(bodyPart.Position) then
				if hitbox:Hit(dummyId) then -- Pass dummyId as target
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

return HitboxService
