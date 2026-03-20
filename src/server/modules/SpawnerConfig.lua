--!strict
--[[
	Class: SpawnerConfig
	Description: Area-based spawner configuration for Hollowed enemies
	Issue #143: HollowedService — Ring 1 enemy spawning with mob caps and collision prevention
	Dependencies: None (pure data + helper functions)

	Defines spawning zones, mob caps per area, and helper functions to:
	- Get all spawn points in a ring
	- Calculate safe spawn positions
	- Enforce mob limits per area
	- Prevent spawn collisions
	- Validate ground height (raycast down to find walkable surface)
]]

local Workspace = game:GetService("Workspace")

export type SpawnZone = {
	AreaName: string,        -- e.g. "Ring1_Verdant", "Ring1_Ruins"
	Ring: number,            -- Ring number (1–5)
	MobCap: number,          -- Max concurrent enemies in this area
	CenterPosition: Vector3, -- Approximate center of the zone
	SearchRadius: number,    -- Radius in studs to search for spawn points
	SpawnRadius: number,     -- Radius around spawn point to check for collisions
}

export type SpawnerConfig = {
	SpawnZones: {SpawnZone},
	CollisionCheckRadius: number,  -- Distance to check before spawning
	RespawnCheckInterval: number,  -- How often (seconds) to check for respawns
	MinSpawnDistance: number,      -- Minimum distance from players to spawn
}

local SpawnerConfig = {}

--[[
	Default spawn zones for Ring 1 (Verdant Shelf).
	Configure these based on your world layout.
]]
function SpawnerConfig.GetDefaultConfig(): SpawnerConfig
	return {
		SpawnZones = {
			{
				AreaName = "Ring1_Verdant",
				Ring = 1,
				MobCap = 4,
				CenterPosition = Vector3.new(0, 5, 0),         -- Adjusted to ground level
				SearchRadius = 40,
				SpawnRadius = 5,
			},
			{
				AreaName = "Ring1_Ruins",
				Ring = 1,
				MobCap = 3,
				CenterPosition = Vector3.new(80, 5, 80),       -- Adjusted to ground level, closer to center
				SearchRadius = 40,
				SpawnRadius = 5,
			},
			{
				AreaName = "Ring1_Cavern",
				Ring = 1,
				MobCap = 2,
				CenterPosition = Vector3.new(-80, 5, -80),     -- Adjusted to ground level, closer to center
				SearchRadius = 40,
				SpawnRadius = 5,
			},
		},
		CollisionCheckRadius = 10,  -- Check 10 studs for other mobs/players
		RespawnCheckInterval = 20,  -- Check every 20 seconds if mobs should respawn
		MinSpawnDistance = 40,      -- Don't spawn within 40 studs of any player
	}
end

--[[
	Find a spawn zone by name.
	@param zoneList - List of spawn zones
	@param areaName - Name of the area (e.g. "Ring1_Verdant")
	@return SpawnZone? - The zone, or nil if not found
]]
function SpawnerConfig.FindZone(zoneList: {SpawnZone}, areaName: string): SpawnZone?
	for _, zone in zoneList do
		if zone.AreaName == areaName then
			return zone
		end
	end
	return nil
end

--[[
	Find all spawn zones for a given ring.
	@param zoneList - List of spawn zones
	@param ring - Ring number
	@return {SpawnZone} - Zones in that ring
]]
function SpawnerConfig.FindZonesByRing(zoneList: {SpawnZone}, ring: number): {SpawnZone}
	local result: {SpawnZone} = {}
	for _, zone in zoneList do
		if zone.Ring == ring then
			table.insert(result, zone)
		end
	end
	return result
end

--[[
	Generate random spawn points within a zone boundary.
	Uses the zone center and search radius to create candidates.

	@param zone - The spawn zone
	@param count - How many candidate points to generate
	@return {Vector3} - Random positions within the zone search radius
]]
function SpawnerConfig.GenerateSpawnCandidates(zone: SpawnZone, count: number): {Vector3}
	local candidates: {Vector3} = {}
	for i = 1, count do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * zone.SearchRadius
		local x = zone.CenterPosition.X + math.cos(angle) * distance
		local z = zone.CenterPosition.Z + math.sin(angle) * distance
		local y = zone.CenterPosition.Y
		table.insert(candidates, Vector3.new(x, y, z))
	end
	return candidates
end

--[[
	Check if a position is safe to spawn at (no other mobs nearby, respects collision radius).

	@param pos - Position to check
	@param existingInstances - Map of active Hollowed instances {instanceId: HollowedData}
	@param collisionRadius - Radius to check for collisions
	@return boolean - True if the position is safe
]]
function SpawnerConfig.IsSpawnPositionSafe(
	pos: Vector3,
	existingInstances: {[string]: any},
	collisionRadius: number
): boolean
	-- Check distance from all existing mobs
	for _, data in existingInstances do
		if data.Position then
			local dist = (pos - data.Position).Magnitude
			if dist < collisionRadius then
				return false  -- Too close to another mob
			end
		end
	end
	return true
end

--[[
	Check if a position is far enough from all players.

	@param pos - Position to check
	@param players - Array of Player instances
	@param minDistance - Minimum safe distance from players
	@return boolean - True if position is safe from players
]]
function SpawnerConfig.IsSpawnPositionFarFromPlayers(
	pos: Vector3,
	players: {any},
	minDistance: number
): boolean
	local Players = game:GetService("Players")
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (pos - root.Position).Magnitude
				if dist < minDistance then
					return false  -- Too close to a player
				end
			end
		end
	end
	return true
end

--[[
	Find ground height at a given horizontal position via raycast.
	Casts a ray downward from the spawn Y and returns the Y value where it hits ground.
	If no ground is found within a reasonable range, returns the original Y or nil.

	@param pos - Position to check (X, Y, Z)
	@param maxRayDistance - How far down to raycast (default 100 studs)
	@return number? - Ground Y position, or nil if no ground found
]]
function SpawnerConfig.FindGroundHeight(pos: Vector3, maxRayDistance: number?): number?
	maxRayDistance = maxRayDistance or 100

	-- Raycast downward from the spawn position
	local rayOrigin = pos + Vector3.new(0, 5, 0)  -- Start 5 studs above to avoid self-collision
	local rayDirection = Vector3.new(0, -maxRayDistance, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {Workspace:FindFirstChild("DebugVisuals")}  -- Ignore any debug elements

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if rayResult then
		-- Return the Y position where we hit ground, add small offset so model sits on surface
		return rayResult.Position.Y + 3  -- +3 studs for typical humanoid root height above ground
	end

	-- No ground found; return nil (spawn will be rejected)
	return nil
end

--[[
	Find the best spawn position within a zone by testing candidates.
	Validates that spawn positions are above ground (via raycast).

	@param zone - Spawn zone to search
	@param existingInstances - Map of active instances
	@param collisionCheckRadius - Radius for collision checks
	@param minPlayerDistance - Minimum distance from players
	@param maxAttempts - How many candidates to test (default 5)
	@return Vector3? - Safe spawn position at ground level, or nil if none found
]]
function SpawnerConfig.FindSafeSpawnPosition(
	zone: SpawnZone,
	existingInstances: {[string]: any},
	collisionCheckRadius: number,
	minPlayerDistance: number,
	maxAttempts: number?
): Vector3?
	maxAttempts = maxAttempts or 5
	local candidates = SpawnerConfig.GenerateSpawnCandidates(zone, maxAttempts)

	for _, candidatePos in candidates do
		-- Find ground height at this position via raycast
		local groundY = SpawnerConfig.FindGroundHeight(candidatePos)
		if not groundY then
			continue  -- No ground found; reject this candidate
		end

		-- Adjust candidate to ground level
		local groundedPos = Vector3.new(candidatePos.X, groundY, candidatePos.Z)

		-- Check collision with other mobs
		if not SpawnerConfig.IsSpawnPositionSafe(groundedPos, existingInstances, collisionCheckRadius) then
			continue
		end

		-- Check distance from players
		if not SpawnerConfig.IsSpawnPositionFarFromPlayers(groundedPos, {}, minPlayerDistance) then
			continue
		end

		-- This position is safe and grounded!
		return groundedPos
	end

	return nil  -- No safe position found
end

return SpawnerConfig
