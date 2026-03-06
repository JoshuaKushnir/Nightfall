--!strict
--[[
	Class: PostureService
	Description: Issue #157 — Inverted posture model.
				 Posture is now a PRESSURE GAUGE that fills when blocking
				 and drains when parrying. Reaching MAX triggers a brief
				 Suppressed stun (0.7 s) during which the player cannot
				 act. Passive decay drains the bar when not blocking.

				 Legacy Stagger / Break API is preserved as _legacy_ stubs
				 so existing call-sites don't hard-error before Phase-4
				 redesign of the Break mechanic.

	Replaces:    Issue #75 drain-toward-zero model.
	Dependencies: StateService, NetworkProvider, DisciplineConfig
	Usage:
		PostureService.GainPosture(player, amount?)   -- on block hit
		PostureService.DrainPosture(player, amount?)  -- on parry / ability
		PostureService.ResetPosture(player)           -- on spawn
		PostureService.IsSuppress(player) -> bool
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateService    = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)

-- ─── Constants (#157 placeholders) ───────────────────────────────────────────

local POSTURE_MAX           = 100   -- full bar = suppressed
local GAIN_BLOCKED_HIT      = 20    -- posture gained per blocked strike
local DRAIN_PARRY           = 30    -- posture drained on successful parry
local DRAIN_PASSIVE         = 8     -- pts/s passive decay when not blocking
local SUPPRESS_DURATION     = 0.7   -- seconds of Suppressed stun
local GAIN_PAUSE_WINDOW     = 0     -- no pause on decay (decays immediately)

-- Legacy constants kept for _legacy_ ExecuteBreak stub
local BREAK_DAMAGE_LEGACY   = 45

-- ─── Types ───────────────────────────────────────────────────────────────────

type PostureState = {
	Current      : number,
	Max          : number,
	Suppressed   : boolean,
	SuppressEnd  : number,   -- tick() when suppression expires
	LastGainTime : number,   -- unused by decay but useful for future talents
}

-- ─── State ───────────────────────────────────────────────────────────────────

local _postures: { [number]: PostureState } = {}

local PostureService = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function _getDiscConfig(player: Player)
	local data = StateService:GetPlayerData(player)
	local id   = data and data.DisciplineId or "Wayward"
	return DisciplineConfig.Get(id)
end

local function _broadcast(eventName: string, ...: any)
	local ev = NetworkProvider:GetRemoteEvent(eventName)
	if ev then ev:FireAllClients(...) end
end

local function _notifyChange(player: Player, state: PostureState)
	_broadcast("PostureChanged", player.UserId, state.Current, state.Max)
end

local function _getOrCreate(player: Player): PostureState
	local uid = player.UserId
	if not _postures[uid] then
		local cfg = _getDiscConfig(player)
		local maxVal = (cfg and cfg.postureMax) or POSTURE_MAX
		_postures[uid] = {
			Current      = 0,
			Max          = maxVal,
			Suppressed   = false,
			SuppressEnd  = 0,
			LastGainTime = 0,
		}
	end
	return _postures[uid]
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	GainPosture — called when the player successfully blocks a hit.
	Fills the pressure gauge. Overflowing max triggers Suppressed.

	@param player  The blocking player.
	@param amount  Points to add (defaults to GAIN_BLOCKED_HIT).
	@return didSuppress : boolean
]]
function PostureService.GainPosture(player: Player, amount: number?): boolean
	local state = _getOrCreate(player)
	if state.Suppressed then return false end

	local gain = amount or GAIN_BLOCKED_HIT
	state.Current     = math.min(state.Max, state.Current + gain)
	state.LastGainTime = tick()
	_notifyChange(player, state)

	if state.Current >= state.Max then
		PostureService.TriggerSuppressed(player)
		return true
	end
	return false
end

--[[
	DrainPosture — called when the player successfully parries, or by
	abilities that relieve posture pressure.

	Source strings (for future discipline multipliers):
	  "Parry" | "Ability" | "Heal"

	@param player  The player whose posture is relieved.
	@param amount  Points to remove (positive number).
	@param source  Optional source tag.
	@return newCurrent : number
]]
function PostureService.DrainPosture(player: Player, amount: number?, source: string?): (boolean, number)
	local state = _getOrCreate(player)
	-- Allow drain even while suppressed (parry interrupt clears suppression faster)

	local drain = amount or DRAIN_PARRY
	state.Current = math.max(0, state.Current - drain)
	_notifyChange(player, state)

	print(("[PostureService] %s posture drained %.0f pts via %s → %.0f/%d"):format(
		player.Name, drain, source or "?", state.Current, state.Max))
	return false, 0   -- signature kept compatible with old callers
end

--[[
	TriggerSuppressed — enters the Suppressed stun state.
	Player cannot attack, block, dodge, or cast for SUPPRESS_DURATION seconds.
	No-ops if already suppressed.
]]
function PostureService.TriggerSuppressed(player: Player)
	local state = _getOrCreate(player)
	if state.Suppressed then return end

	state.Suppressed  = true
	state.SuppressEnd = tick() + SUPPRESS_DURATION
	state.Current     = state.Max   -- clamp at max, decay will clear it

	-- Character attribute — read by CombatService / ActionController guard checks
	local char = player.Character
	if char then
		char:SetAttribute("IsSuppressed", true)
	end

	-- Set player state to Stunned (blocks CanPerformAction in StateService)
	StateService:SetPlayerState(player, "Stunned")

	-- Broadcast so client plays suppressed VFX
	_broadcast("Staggered", player.UserId, SUPPRESS_DURATION)
	-- NOTE: reuses "Staggered" event name so CombatFeedbackUI stagger flash
	-- still fires without a new network event. Rename in Phase 4 if desired.

	print(("[PostureService] 🔒 %s Suppressed for %.1fs (posture maxed)"):format(
		player.Name, SUPPRESS_DURATION))

	task.delay(SUPPRESS_DURATION, function()
		local stateNow = _postures[player.UserId]
		if not stateNow then return end

		stateNow.Suppressed = false
		-- Posture stays at max and begins decaying immediately via Heartbeat
		_notifyChange(player, stateNow)

		local exitChar = player.Character
		if exitChar then
			exitChar:SetAttribute("IsSuppressed", nil)
		end

		-- Return player to Idle
		local data = StateService:GetPlayerData(player)
		if data and data.State == "Stunned" then
			StateService:SetPlayerState(player, "Idle")
		end

		print(("[PostureService] %s Suppressed expired, posture decaying"):format(player.Name))
	end)
end

--[[
	IsSuppress — returns true while the player is in the Suppressed window.
]]
function PostureService.IsSuppress(player: Player): boolean
	local uid   = player.UserId
	local state = _postures[uid]
	if not state then return false end
	return state.Suppressed and tick() < state.SuppressEnd
end

--[[
	GetPosture — returns (current, max).
]]
function PostureService.GetPosture(player: Player): (number, number)
	local state = _getOrCreate(player)
	return state.Current, state.Max
end

--[[
	ResetPosture — hard-reset to 0 (on respawn).
]]
function PostureService.ResetPosture(player: Player)
	local uid = player.UserId
	local cfg = _getDiscConfig(player)
	local maxVal = (cfg and cfg.postureMax) or POSTURE_MAX
	_postures[uid] = {
		Current      = 0,
		Max          = maxVal,
		Suppressed   = false,
		SuppressEnd  = 0,
		LastGainTime = 0,
	}
	_broadcast("PostureChanged", uid, 0, maxVal)
end

-- ─── Legacy stubs (#75 → Phase 4) ────────────────────────────────────────────
-- Kept so existing call-sites in DefenseService / CombatService don't crash.
-- These are no-ops in the new model; Break mechanic will be redesigned in Phase 4.

function PostureService.IsStaggered(_player: Player): boolean
	return false   -- _legacy_: Stagger replaced by Suppressed
end

function PostureService.TriggerStagger(player: Player)
	-- _legacy_: redirect to TriggerSuppressed so old callers still produce a stun
	PostureService.TriggerSuppressed(player)
end

function PostureService.RestorePosture(player: Player, amount: number)
	-- _legacy_: maps to DrainPosture (reducing pressure)
	PostureService.DrainPosture(player, amount, "Heal")
end

function PostureService.ExecuteBreak(_attacker: Player, _target: Player): boolean
	-- _legacy_: Break mechanic deferred to Phase 4
	warn("[PostureService] ExecuteBreak called — Break mechanic deferred to Phase 4 (#157)")
	return false
end

-- ─── Passive decay Heartbeat ─────────────────────────────────────────────────

local function _startDecayLoop()
	RunService.Heartbeat:Connect(function(dt: number)
		for uid, state in _postures do
			if state.Suppressed then continue end
			if state.Current <= 0 then continue end

			-- Check if this player is actively blocking — no decay while blocking
			local player = Players:GetPlayerByUserId(uid)
			if not player then continue end

			local data = StateService:GetPlayerData(player)
			local isBlocking = data and data.State == "Blocking"
			if isBlocking then continue end

			state.Current = math.max(0, state.Current - DRAIN_PASSIVE * dt)
			_notifyChange(player, state)
		end
	end)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function PostureService:Init()
	print("[PostureService] Initializing (#157 inverted model)...")

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)   -- let StateService register the player first
			PostureService.ResetPosture(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_postures[player.UserId] = nil
	end)

	print("[PostureService] Initialized")
end

function PostureService:Start()
	_startDecayLoop()
	print("[PostureService] Started — inverted posture model active")
end

return PostureService