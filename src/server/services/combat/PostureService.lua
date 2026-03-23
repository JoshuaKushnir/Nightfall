--!strict
-- Class: PostureService
-- Description:
--   Server-authoritative posture system (Issue #157).
--   Implements posture as a per-character resource that starts full at a
--   discipline-configured max. Handles:
--     - Posture drain on blocked hits (postureDamage)
--     - Parry behavior (posture refund / overcap buffer / stress release)
--     - Regeneration with adaptive "stress" multiplier
--     - Regen pause after posture-damaging hits (0.3s per hit)
--     - Posture break (zero → suppressed/stunned)
--     - Block-breaking move handling (forces break + full HP damage)
--
--   The service exposes a concise API used by CombatService/HitboxService:
--     PostureService:InitCharacter(player)
--     PostureService:DrainPosture(player, amount, opts)
--     PostureService:GainPosture(player, amount, opts)
--     PostureService:BreakPosture(player, reason, opts)
--     PostureService:Update(dt) -- public for testing; internal Heartbeat drives this
--
-- Dependencies:
--   StateService, NetworkProvider, DisciplineConfig, RunService
--   (CombatService may call into this service, so PostureService avoids hard
--    requiring CombatService at module top-level to prevent circular requires.)
--
-- Notes:
--   - All posture changes are server-side authoritative.
--   - Clients receive posture updates via RemoteEvent "PostureChanged" and
--     CombatData/related events. Character attributes are also kept in sync
--     (Posture, PostureMax, PostureStress, IsSuppressed).
--   - Tunables are read from DisciplineConfig where possible; remaining tuning
--     values are kept in the `TUNING` table for quick balance.
--
-- Issue reference: #157
--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateService    = require(ReplicatedStorage.Shared.modules.core.StateService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.progression.DisciplineConfig)

-- Optional safe require for CombatService when needed (avoid module-cycle at top)
local function safeRequireCombat()
	local ok, mod = pcall(function()
		return require(game:GetService("ServerScriptService").Server.services.combat.CombatService)
	end)
	if ok then return mod end
	return nil
end

-- Tunables local to PostureService (kept small & explicit)
local TUNING = {
	-- regen pause after receiving posture-damaging hit (seconds per hit)
	regenPausePerHit = 0.3,

	-- Parry: how much overcap buffer a parry grants (absolute points)
	parryOvercap = 15,

	-- Parry: how much stress is released on a successful parry (0..1)
	parryStressRelease = 0.25,

	-- Stress decay (per second) when not under pressure
	stressDecayPerSec = 0.5,

	-- Stress accumulation scale (how hits map to 0..1 stress)
	-- stress += (amount / postureMax) * stressPerPoint
	stressPerPoint = 1.0, -- nominal mapping; discipline-specific talents may modify

	-- Maximum allowed overcap beyond postureMax (absolute)
	overcapLimit = 20,

	-- Block-break stun duration range (seconds)
	blockBreakMinStun = 0.4,
	blockBreakMaxStun = 0.6,

	-- Default base regen fallback (if discipline missing)
	defaultPostureRecovery = 6,
}

-- Per-player posture state
type PostureState = {
	Current : number,
	Max : number,
	Overcap : number,            -- temporary buffer above Max from parries (0..overcapLimit)
	RegenPausedUntil : number,   -- tick() until regen resumes
	Stress : number,             -- 0..1 metric reflecting recent pressure
	LastPressureTime : number,   -- tick() when last pressured
	Suppressed : boolean,
	SuppressEnd : number,
}

local _states : {[number]: PostureState} = {}

local PostureService = {}

-- Helper: network event getter
local function _getPostureEvent()
	return NetworkProvider:GetRemoteEvent("PostureChanged")
end

local function _firePostureChanged(player: Player, state: PostureState)
	local ev = _getPostureEvent()
	-- send minimal packet for client HUD (current, max, overcap, stress, suppressed)
	if ev and player and player.Parent then
		ev:FireClient(player, {
			Current = state.Current,
			Max = state.Max,
			Overcap = state.Overcap,
			Stress = state.Stress,
			Suppressed = state.Suppressed,
		})
	end
end

-- Internal: apply character attributes for client-side display & guards
local function _applyCharAttributes(player: Player, state: PostureState)
	local char = player.Character
	if not char then return end
	-- Use attributes so client controllers can read them cheaply
	char:SetAttribute("Posture", math.floor(state.Current))
	char:SetAttribute("PostureMax", math.floor(state.Max))
	char:SetAttribute("PostureOvercap", math.floor(state.Overcap))
	char:SetAttribute("PostureStress", math.clamp(state.Stress, 0, 1))
	char:SetAttribute("IsSuppressed", state.Suppressed or nil)
end

local function _getDiscCfgForPlayer(player: Player)
	local data = StateService:GetPlayerData(player)
	local id = data and data.DisciplineId or "Wayward"
	return DisciplineConfig.Get(id)
end

local function _initStateForPlayer(player: Player)
	local uid = player.UserId
	local cfg = _getDiscCfgForPlayer(player)
	local maxVal = (cfg and cfg.postureMax) or TUNING.defaultPostureRecovery and 100 or 100
	local st : PostureState = {
		Current = maxVal,         -- starts full
		Max = maxVal,
		Overcap = 0,
		RegenPausedUntil = 0,
		Stress = 0,
		LastPressureTime = 0,
		Suppressed = false,
		SuppressEnd = 0,
	}
	_states[uid] = st

	-- apply attributes on character if present
	_applyCharAttributes(player, st)

	-- notify client (initial)
	_firePostureChanged(player, st)

	return st
end

-- Public: explicitly initialize character posture (callable by other services)
function PostureService.InitCharacter(player: Player)
	if not player then return end
	local uid = player.UserId
	local existing = _states[uid]
	if existing then
		-- refresh discipline-dependent caps (if changed)
		local cfg = _getDiscCfgForPlayer(player)
		local maxVal = (cfg and cfg.postureMax) or existing.Max
		existing.Max = maxVal
		if existing.Current > existing.Max + TUNING.overcapLimit then
			existing.Current = existing.Max + TUNING.overcapLimit
		end
		_applyCharAttributes(player, existing)
		_firePostureChanged(player, existing)
		return existing
	end
	return _initStateForPlayer(player)
end

-- Internal: send combat-data style posture replication (compat with HUD pipeline)
local function _sendCombatDataToPlayer(player: Player, state: PostureState)
	-- Keep this minimal — StateSyncService/Combat pipeline may also mirror these.
	local ev = NetworkProvider:GetRemoteEvent("CombatData")
	if ev then
		-- CombatDataPacket expected fields: HP, MaxHP, Mana, MaxMana, Posture, MaxPosture, ...
		ev:FireClient(player, {
			Posture = state.Current,
			MaxPosture = state.Max,
		})
	end
	-- Also send a posture-specific packet if present (PostureChanged event already covers it)
end

-- Public: DrainPosture
--   Called when posture should be removed (blocked hits, some abilities)
--   opts table:
--     .BypassBlockMultiplier (bool) -- if true, do not apply discipline block multiplier
--     .IsBlocking (bool) -- whether target was blocking (server should use StateService)
--     .IsBlockBreaker (bool) -- whether this hit is flagged to always break
--     .Source (string) -- informational tag ("Hit","Ability","Aspect","BlockBreak")
-- Returns: broke:boolean (true if posture dropped to 0 and break occurred)
function PostureService.DrainPosture(player: Player, amount: number, opts: {[string]: any}?)
	if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	local uid = player.UserId
	local state = _states[uid] or _initStateForPlayer(player)
	if amount == nil or amount <= 0 then return false end

	opts = opts or {}
	local isBlocking = opts.IsBlocking
	-- Apply discipline block multiplier when blocking and modifier not bypassed
	if isBlocking and not opts.BypassBlockMultiplier then
		local cfg = _getDiscCfgForPlayer(player)
		local mult = (cfg and cfg.postureBlockMultiplier) or 1.0
		amount = amount * mult
	end

	-- Mark pressure time and increase stress proportionally
	local pressureNormalized = math.clamp(amount / math.max(1, state.Max), 0, 1)
	state.Stress = math.clamp(state.Stress + pressureNormalized * TUNING.stressPerPoint, 0, 1)
	state.LastPressureTime = tick()

	-- Pause regen for regenPausePerHit seconds per spec
	local pause = TUNING.regenPausePerHit
	state.RegenPausedUntil = math.max(state.RegenPausedUntil, tick() + pause)

	-- If blocked by a block-breaking move, force break immediately
	local isBlockBreaker = opts.IsBlockBreaker
	if isBlocking and isBlockBreaker then
		-- Full HP damage should be handled upstream in CombatService; we only trigger break here
		PostureService.BreakPosture(player, "BlockBreaker", opts)
		return true
	end

	-- Apply drain
	local prior = state.Current
	state.Current = math.max(0, state.Current - amount)

	-- If posture reached zero due to this drain, trigger break
	if state.Current <= 0 then
		PostureService.BreakPosture(player, "Drained", opts)
		_applyCharAttributes(player, state)
		_firePostureChanged(player, state)
		_sendCombatDataToPlayer(player, state)
		return true
	end

	-- Persist and notify
	_applyCharAttributes(player, state)
	_firePostureChanged(player, state)
	_sendCombatDataToPlayer(player, state)

	return false
end

-- Public: GainPosture
--   Called to add posture (e.g., successful parry restores posture and grants overcap buffer)
--   amount: positive number to add to current posture (not overcap)
--   opts:
--     .IsParry (bool) -- grants overcap and releases stress
--     .Source (string)
-- Returns: newCurrent:number
function PostureService.GainPosture(player: Player, amount: number?, opts: {[string]: any}?)
	if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then return 0 end
	local uid = player.UserId
	local state = _states[uid] or _initStateForPlayer(player)
	local add = amount or 0
	opts = opts or {}

	-- Parry behavior: refund posture AND give temporary overcap buffer and reduce stress
	if opts.IsParry then
		-- Add base amount to posture
		state.Current = math.min(state.Max + TUNING.overcapLimit, state.Current + add)
		-- Grant overcap buffer (separate counter) but never exceed overcapLimit
		state.Overcap = math.min(TUNING.overcapLimit, state.Overcap + TUNING.parryOvercap)
		-- Reduce stress
		state.Stress = math.clamp(state.Stress - TUNING.parryStressRelease, 0, 1)
		-- Parry should also clear a small regen pause so the player recovers quickly
		state.RegenPausedUntil = math.max(state.RegenPausedUntil, tick() + 0.05)
	else
		-- Non-parry gains simply increase posture up to max + current overcap
		local cap = state.Max + state.Overcap
		state.Current = math.min(cap, state.Current + add)
	end

	state.LastPressureTime = tick()
	_applyCharAttributes(player, state)
	_firePostureChanged(player, state)
	_sendCombatDataToPlayer(player, state)

	return state.Current
end

-- Public: BreakPosture
--   Force a posture break / suppressed stun on the target.
--   reason: string describing cause ("Drained","BlockBreaker", etc.)
--   opts: optional table for extra tuning (e.g., explicit duration)
function PostureService.BreakPosture(player: Player, reason: string?, opts: {[string]: any}?)
	if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local uid = player.UserId
	local state = _states[uid] or _initStateForPlayer(player)

	-- If already suppressed, extend or ignore
	if state.Suppressed and tick() < state.SuppressEnd then
		-- Optionally extend by small amount if block-break is stronger
		local extend = 0
		if reason == "BlockBreaker" then extend = 0.15 end
		state.SuppressEnd = state.SuppressEnd + extend
		return
	end

	-- Zero posture and enter suppressed
	state.Current = 0
	state.Overcap = 0
	state.Stress = 1 -- high stress on break
	state.Suppressed = true

	-- Determine duration (use discipline staggerDuration for base; block-break stronger)
	local cfg = _getDiscCfgForPlayer(player)
	local baseStagger = (cfg and cfg.staggerDuration) or 0.7
	local duration = baseStagger
	if reason == "BlockBreaker" then
		-- stronger variant
		duration = math.clamp((TUNING.blockBreakMinStun + TUNING.blockBreakMaxStun)/2, TUNING.blockBreakMinStun, TUNING.blockBreakMaxStun)
	end
	if opts and opts.ForceDuration then duration = opts.ForceDuration end

	state.SuppressEnd = tick() + duration

	-- Set character attributes and state
	local char = player.Character
	if char then
		char:SetAttribute("Posture", 0)
		char:SetAttribute("IsSuppressed", true)
	end

	-- Set player state using StateService to ensure consistent state machine integration
	StateService:SetPlayerState(player, "Stunned")

	-- Broadcast to client to play block-break/stagger VFX and HUD feedback
	local evStag = NetworkProvider:GetRemoteEvent("Staggered")
	if evStag then
		evStag:FireClient(player, duration)
	end

	-- Also fire PostureChanged so HUD updates immediately
	_firePostureChanged(player, state)
	_sendCombatDataToPlayer(player, state)

	-- Schedule suppression end logic
	task.delay(duration, function()
		local s = _states[uid]
		if not s then return end
		s.Suppressed = false
		-- Clear suppress attribute
		local c = player.Character
		if c then
			c:SetAttribute("IsSuppressed", nil)
		end

		-- Return player to Idle (only if still Stunned)
		local pdata = StateService:GetPlayerData(player)
		if pdata and pdata.State == "Stunned" then
			StateService:SetPlayerState(player, "Idle")
		end

		-- Notify client
		_firePostureChanged(player, s)
		_sendCombatDataToPlayer(player, s)
	end)
end

-- Public: GetPosture (utility)
function PostureService.GetPosture(player: Player)
	if not player then return 0, 0 end
	local st = _states[player.UserId]
	if not st then
		return 0, 0
	end
	return st.Current, st.Max
end

-- Update loop — exposed publicly for tests; Heartbeat will call this
function PostureService.Update(dt: number)
	-- Iterate over copy to avoid mutation issues
	for uid, state in pairs(_states) do
		-- Find player
		local player = Players:GetPlayerByUserId(uid)
		if not player or not player.Parent then
			_states[uid] = nil
			continue
		end

		-- Handle suppression expiry
		if state.Suppressed and tick() >= state.SuppressEnd then
			state.Suppressed = false
			local char = player.Character
			if char then char:SetAttribute("IsSuppressed", nil) end
			-- If still in Stunned state, return to Idle
			local pdata = StateService:GetPlayerData(player)
			if pdata and pdata.State == "Stunned" then
				StateService:SetPlayerState(player, "Idle")
			end
			_firePostureChanged(player, state)
		end

		-- Skip regen while suppressed
		if state.Suppressed then
			continue
		end

		-- Skip regen if paused (recent pressure)
		if tick() < state.RegenPausedUntil then
			-- still cannot regen; continue stress decay logic below
		else
			-- Compute regen using discipline base and stress multiplier
			local cfg = _getDiscCfgForPlayer(player)
			local baseRegen = (cfg and cfg.postureRecovery) or TUNING.defaultPostureRecovery

			-- Interpret "stress" such that more stress => faster regen.
			-- We apply a multiplier: regen = baseRegen * (1 + stress)
			local regenMultiplier = 1 + math.clamp(state.Stress, 0, 1)
			local regenAmount = baseRegen * regenMultiplier * dt

			-- Apply regen (do not exceed Max + Overcap)
			local cap = state.Max + state.Overcap
			if state.Current < cap then
				state.Current = math.min(cap, state.Current + regenAmount)
				_applyCharAttributes(player, state)
				_firePostureChanged(player, state)
				_sendCombatDataToPlayer(player, state)
			end

			-- If we've regened back above Max, gradually burn down Overcap
			if state.Current >= state.Max and state.Overcap > 0 then
				-- slowly decay overcap as it's temporary; use a small fraction of regen
				local overcapDecay = math.max(1, baseRegen * dt * 0.5)
				state.Overcap = math.max(0, state.Overcap - overcapDecay)
				_applyCharAttributes(player, state)
				_firePostureChanged(player, state)
			end
		end

		-- Stress decay when not pressured
		-- If no pressure for some time, decay stress towards 0
		if tick() - state.LastPressureTime > 0.15 then
			state.Stress = math.max(0, state.Stress - TUNING.stressDecayPerSec * dt)
			_applyCharAttributes(player, state)
		end
	end
end

-- Internal: Heartbeat driver
local function _startHeartbeat()
	RunService.Heartbeat:Connect(function(dt)
		PostureService.Update(dt)
	end)
end

-- Lifecycle: Init / Start
function PostureService:Init()
	print("[PostureService] Initializing (full posture model)")

	-- Ensure player lifecycle is tracked
	Players.PlayerAdded:Connect(function(player)
		-- When the character is added, initialize posture attributes
		player.CharacterAdded:Connect(function(char)
			-- Slight delay so StateService has populated the player's data
			task.delay(0.5, function()
				PostureService.InitCharacter(player)
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_states[player.UserId] = nil
	end)
end

function PostureService:Start()
	_startHeartbeat()
	print("[PostureService] Started")
end

-- Expose a debug dump of state (useful for tests)
function PostureService._DebugDump()
	local out = {}
	for uid, st in pairs(_states) do
		out[uid] = {
			Current = st.Current, Max = st.Max, Overcap = st.Overcap,
			Stress = st.Stress, Suppressed = st.Suppressed,
		}
	end
	return out
end

return PostureService
