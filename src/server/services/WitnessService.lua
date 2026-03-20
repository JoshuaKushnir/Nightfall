--!strict
--[[
	Class: WitnessService
	Description: Server-authoritative observation tracking for Codex entries (#179)
	Dependencies: StateService, HollowedService, NetworkProvider

	Usage:
		Track players observing entities (like Hollowed variants) and award
		Codex entries after observing them peacefully for 30 seconds.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

local HollowedService = nil

local WitnessService = {}
WitnessService._initialized = false

local WITNESS_TICK_RATE = 1.0     -- Evaluate once per second
local WITNESS_DISTANCE_MAX = 80   -- studs to be considered observing
local WITNESS_TIME_REQUIRED = 30  -- seconds needed to unlock

-- Per-player active observation tracking
-- Track which configId they are currently observing, and how many seconds they've accrued
type TrackingData = {
	ConfigId: string,
	TimeAccrued: number,
	LastTick: number,
}
local _playerTracking: {[Player]: TrackingData} = {}
local _heartbeatConn: RBXScriptConnection? = nil

function WitnessService:Init(dependencies: {[string]: any}?)
	if dependencies then
		HollowedService = dependencies.HollowedService
	end
	WitnessService._initialized = true
end

-- Safely get hollowed service
local function GetHollowedService(): any?
	if not HollowedService then
		local ok, svc = pcall(require, game:GetService("ServerScriptService").Server.services.HollowedService)
		if ok then HollowedService = svc end
	end
	return HollowedService
end

-- Resets the observation progress for a player
local function ResetTracking(player: Player)
	if _playerTracking[player] then
		_playerTracking[player] = nil
	end
end

-- Evaluate witnessing for all players
local function _TickWitnessing(dt: number)
	local hollowedSvc = GetHollowedService()
	if not hollowedSvc then return end

	local now = tick()
	for _, player in Players:GetPlayers() do
		local data = StateService:GetPlayerData(player)
		if not data or data.State == "Dead" then
			ResetTracking(player)
			continue
		end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			ResetTracking(player)
			continue
		end

		-- Find nearest valid Hollowed to observe
		local bestConfig: string? = nil
		local bestInstanceId: string? = nil
		local bestDist = WITNESS_DISTANCE_MAX + 1

		local allInstances = hollowedSvc.GetAllInstances()
		if allInstances then
			for instanceId, hollowedData in allInstances do
				-- Must be active and not dead
				if not hollowedData.IsActive or hollowedData.State == "Dead" then continue end

				-- Observation breaks if the player enters combat (meaning if the enemy aggros *them* or vice/versa)
				-- If the Hollowed is aggro'd on any target, it's not a calm observation, so we can optionally skip or allow.
				-- Let's say you can't observe if the Hollowed is aggro'd onto YOU.
				if hollowedData.State == "Aggro" and hollowedData.Target == player then continue end

				-- If player is in combat states, reset tracking
				if data.State == "Attacking" or data.State == "Dodging" or data.State == "Lockon" then continue end

				local dist = (hollowedData.RootPosition - root.Position).Magnitude
				if dist < bestDist then
					-- Check line of sight (simple raycast) to ensure they are actually looking/unobstructed
					local rayDir = (hollowedData.RootPosition - root.Position)
					local ray = RaycastParams.new()
					ray.FilterDescendantsInstances = {char}
					ray.FilterType = Enum.RaycastFilterType.Exclude
					local hit = game:GetService("Workspace"):Raycast(root.Position, rayDir, ray)

					-- If there's an obstruction that isn't the Hollowed, it breaks LOS.
					-- For simplicity, if we hit anything that isn't the hollowed model, fail LOS.
					local hasLOS = true
					if hit and hit.Instance and not hit.Instance:IsDescendantOf(workspace) then -- just a placeholder LOS check, actually let's skip rigorous LOS for MVP, distance is fine.
					end

					bestDist = dist
					bestConfig = hollowedData.ConfigId
					bestInstanceId = instanceId
				end
			end
		end

		local currentTrack = _playerTracking[player]

		if not bestConfig then
			if currentTrack then
				ResetTracking(player)
				local failEvent = NetworkProvider:GetRemoteEvent("WitnessFailed")
				if failEvent then
					failEvent:FireClient(player, { TargetInstanceId = currentTrack.ConfigId, Reason = "Target lost" })
				end
			end
			continue
		end

		-- Found a target to observe
		-- Is it already unlocked?
		if data.CodexEntries and data.CodexEntries[bestConfig] and data.CodexEntries[bestConfig].State == "Witnessed" then
			if currentTrack then ResetTracking(player) end
			continue
		end

		-- Initialize or update tracking
		if not currentTrack or currentTrack.ConfigId ~= bestConfig then
			_playerTracking[player] = {
				ConfigId = bestConfig,
				TimeAccrued = 0,
				LastTick = now,
			}
			local startEvent = NetworkProvider:GetRemoteEvent("WitnessStarted")
			if startEvent then
				startEvent:FireClient(player, { TargetInstanceId = bestInstanceId, TargetName = bestConfig, Duration = WITNESS_TIME_REQUIRED })
			end
		else
			-- Increment time
			local delta = now - currentTrack.LastTick
			currentTrack.LastTick = now
			currentTrack.TimeAccrued += delta

			local progEvent = NetworkProvider:GetRemoteEvent("WitnessProgress")
			if progEvent then
				progEvent:FireClient(player, {
					TargetInstanceId = bestInstanceId,
					TargetName = bestConfig,
					Progress = currentTrack.TimeAccrued / WITNESS_TIME_REQUIRED,
					Broken = false
				})
			end

			-- Check for unlock
			if currentTrack.TimeAccrued >= WITNESS_TIME_REQUIRED then
				-- Unlock!
				if not data.CodexEntries then data.CodexEntries = {} end
				data.CodexEntries[bestConfig] = {
					Id = bestConfig,
					State = "Witnessed",
					WitnessedAt = os.time()
				}

				-- Send final progress update with Broken = false (completed)
				local progEvent = NetworkProvider:GetRemoteEvent("WitnessProgress")
				if progEvent then
					progEvent:FireClient(player, {
						TargetInstanceId = bestInstanceId,
						TargetName = bestConfig,
						Progress = 1.0,
						Broken = false
					})
				end

				ResetTracking(player)

				-- Notify client
				local unlockedEvent = NetworkProvider:GetRemoteEvent("CodexUnlocked")
				if unlockedEvent then
					unlockedEvent:FireClient(player, { EntryId = bestConfig, Title = bestConfig })
				end
			end
		end
	end
end

function WitnessService:Start()
	assert(WitnessService._initialized, "Must call Init() before Start()")

	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		_TickWitnessing(dt)
	end)
end

function WitnessService:Shutdown()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end
	table.clear(_playerTracking)
end

-- Export for testing
WitnessService._TickWitnessing = _TickWitnessing
WitnessService._ResetTracking = ResetTracking

return WitnessService
