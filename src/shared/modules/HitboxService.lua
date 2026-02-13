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

type Hitbox = HitboxTypes.Hitbox
type HitboxConfig = HitboxTypes.HitboxConfig
type HitData = HitboxTypes.HitData

local HitboxService = {}

-- Storage
local ActiveHitboxes: {Hitbox} = {}
local HitboxCounter = 0

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
			end
		end,
		
		Expire = function(self: Hitbox)
			self.Active = false
			table.remove(ActiveHitboxes, table.find(ActiveHitboxes, self) or -1)
			
			if self.Config.OnExpire then
				task.spawn(self.Config.OnExpire)
			end
			
			print(`[HitboxService] Hitbox expired: {self.Id}`)
		end,
		
		IsValidTarget = function(self: Hitbox, target: Player): boolean
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
			
			-- State validation
			if self.Config.StunAffinity then
				local targetData = StateService:GetPlayerData(target)
				if not targetData or not table.find(self.Config.StunAffinity, targetData.State) then
					return false
				end
			end
			
			-- Target must exist
			if not target.Parent then
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
				local distance = (self.Config.Position - targetPosition).Magnitude
				return distance <= radius
				
			elseif shape == "Box" then
				if not self.Config.Position or not self.Config.Size then
					return false
				end
				
				local halfSize = self.Config.Size / 2
				local offset = (targetPosition - self.Config.Position).Abs()
				return offset.X <= halfSize.X and offset.Y <= halfSize.Y and offset.Z <= halfSize.Z
				
			elseif shape == "Raycast" then
				if not self.Config.Origin or not self.Config.Direction or not self.Config.Length then
					return false
				end
				
				-- Vector from ray origin to point
				local toTarget = targetPosition - self.Config.Origin
				local rayDir = self.Config.Direction.Unit
				
				-- Project point onto ray
				local tClosest = math.max(0, math.min(self.Config.Length, toTarget:Dot(rayDir)))
				local closest = self.Config.Origin + (rayDir * tClosest)
				
				-- Distance to line (use small tolerance for sphere radius)
				local distance = (targetPosition - closest).Magnitude
				return distance <= 3 -- 3 stud radius for raycast
			end
			
			return false
		end,
	}
	
	table.insert(ActiveHitboxes, hitbox)
	
	-- Auto-expire
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
	
	for _, player in Players:GetPlayers() do
		if player == hitbox.Config.Owner then
			continue
		end
		
		if not hitbox:IsValidTarget(player) then
			continue
		end
		
		-- Get target position
		local character = player.Character
		if not character then
			continue
		end
		
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
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

return HitboxService
