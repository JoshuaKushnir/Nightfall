--!strict
--[[
	PostureService.lua

	Issue #75: Posture + HP — dual health model with Break and Stagger
	Epic #49: Phase 2 - Combat & Fluidity

	Manages the server-side Posture resource for all players.

	Posture is a secondary health bar (distinct from both HP and Breath):
	  • Drains when a player blocks a hit, takes an unguarded strike, or is hit
	    by an Aspect ability.
	  • Regenerates passively when the player has not been hit for REGEN_PAUSE_WINDOW
	    seconds. Regen is faster while NOT blocking.
	  • Reaching 0 triggers Stagger state (vulnerability window ~0.8 s).
	  • During Stagger the attacker may fire a Break – a deliberate heavy strike
	    that deals significant HP damage and immediately exits the Stagger.

	Network events broadcast on every change:
	  PostureChanged  → { PlayerId, Current, Max }        – for posture bars
	  Staggered       → { PlayerId, Duration }             – for VFX / state
	  BreakExecuted   → { AttackerId, TargetId, Damage }  – for hit-stop / SFX

	Dependencies injected in :Start():
	  StateService   – SetPlayerState / GetPlayerData
	  NetworkProvider – remote event access
	  CombatService  – ApplyBreakDamage callback (lazy to avoid circular require)
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateService    = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

-- ─── Constants ────────────────────────────────────────────────────────────────

-- discipline-influenced constants will be resolved per-player
local DEFAULT_POSTURE_MAX          = 100  -- fallback
local DEFAULT_REGEN_RATE           = 8    -- passive
local DEFAULT_REGEN_RATE_BLOCKING  = 3    -- while blocking
local REGEN_PAUSE_WINDOW           = 1.8  -- seconds with no hit before regen resumes
-- STAGGER_DURATION replaced by per-player lookup

-- helper to obtain discipline config for a player
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)

local function _getDiscConfig(player: Player)
	local data = StateService:GetPlayerData(player)
	local id = data and data.DisciplineId or "Wayward"
	return DisciplineConfig.Get(id)
end
local BREAK_DAMAGE         = 45   -- flat HP damage on a successful Break

-- Drain per-hit source
local DRAIN_BLOCKED_HIT    = 20  -- posture drain when the player blocks a strike
local DRAIN_UNGUARDED_HIT  = 8   -- posture drain from an unguarded hit
local DRAIN_ASPECT_HIT     = 25  -- posture drain from an Aspect ability

-- ─── Types ────────────────────────────────────────────────────────────────────

type PostureState = {
	Current     : number,
	Max         : number,
	LastHitTime : number,  -- tick() of the most recent drain
	Staggered   : boolean,
	StaggerEnd  : number,  -- tick() when Stagger expires
}

-- ─── Internal state ──────────────────────────────────────────────────────────

-- Keyed by Player.UserId.  Populated on CharacterAdded, cleared on leave.
local _postures: {[number]: PostureState} = {}

-- Lazy-required at :Start() to avoid circular require
local CombatService: any = nil

local PostureService = {}

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _broadcast(event: string, ...)
	local remote = NetworkProvider:GetRemoteEvent(event :: any)
	if remote then
		remote:FireAllClients(...)
	end
end

local function _fireClient(player: Player, event: string, ...)
	local remote = NetworkProvider:GetRemoteEvent(event :: any)
	if remote then
		remote:FireClient(player, ...)
	end
end

--[[
	Return (and lazily create) the PostureState for a player.
]]
local function _getOrCreate(player: Player): PostureState
	local uid = player.UserId
	if not _postures[uid] then
		-- determine max posture from discipline
		local cfg = _getDiscConfig(player)
		local maxVal = cfg and cfg.postureMax or DEFAULT_POSTURE_MAX
		_postures[uid] = {
			Current     = maxVal,
			Max         = maxVal,
			LastHitTime = 0,
			Staggered   = false,
			StaggerEnd  = 0,
		}
	end
	return _postures[uid]
end

--[[
	Broadcast PostureChanged so clients can update posture bars.
]]
local function _notifyChange(player: Player, state: PostureState)
	_broadcast("PostureChanged", player.UserId, state.Current, state.Max)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Return the current / max posture for a player.
	@return (current, max) or (100, 100) if not tracked yet.
]]
function PostureService.GetPosture(player: Player): (number, number)
	local uid = player.UserId
	local state = _postures[uid]
	if not state then return POSTURE_MAX, POSTURE_MAX end
	return state.Current, state.Max
end

--[[
	Drain posture by `amount` from the given drain source.
	Returns true when posture hits 0 and Stagger is triggered.

	@param player   The player taking posture damage.
	@param amount   Points to drain (positive).
	@param source   One of "Blocked" | "Unguarded" | "Aspect"; determines drain table.
	                Ignored if `amount` is provided directly.
	@return didBreak : boolean
]]
function PostureService.DrainPosture(player: Player, amount: number?, source: string?): (boolean, number)
	local state = _getOrCreate(player)

	if state.Staggered then
		-- Already staggered; don't double-drain
		return false, 0
	end

	-- Determine drain amount from source lookup when caller doesn't specify
	local drain: number
	if amount then
		drain = amount
	elseif source == "Blocked" then
		drain = DRAIN_BLOCKED_HIT
	elseif source == "Aspect" then
		drain = DRAIN_ASPECT_HIT
	else
		drain = DRAIN_UNGUARDED_HIT  -- "Unguarded" or unknown
	end
	-- apply discipline-specific multiplier for blocked hits
	if source == "Blocked" then
		local cfg = _getDiscConfig(player)
		if cfg and cfg.BlockDrainMultiplier then
			drain = drain * cfg.BlockDrainMultiplier
		end
	end

	-- compute overflow (amount beyond 0)
	local prev = state.Current
	local overflow = math.max(0, drain - prev)

	state.LastHitTime = tick()
	state.Current = math.max(0, state.Current - drain)

	_notifyChange(player, state)

	-- Trigger Stagger when posture reaches 0
	if state.Current <= 0 then
		PostureService.TriggerStagger(player)
		return true, overflow
	end
	return false, overflow
end

--[[
	Restore posture by `amount`.  Used by healing abilities or manual resets.
	Capped at Max; does not exit Stagger.
]]
function PostureService.RestorePosture(player: Player, amount: number)
	local state = _getOrCreate(player)
	state.Current = math.min(state.Max, state.Current + amount)
	_notifyChange(player, state)
end

--[[
	Hard-reset a player's posture to max (on respawn, etc.).
]]
function PostureService.ResetPosture(player: Player)
	local uid = player.UserId
	local cfg = _getDiscConfig(player)
	local maxVal = cfg and cfg.postureMax or DEFAULT_POSTURE_MAX
	_postures[uid] = {
		Current     = maxVal,
		Max         = maxVal,
		LastHitTime = 0,
		Staggered   = false,
		StaggerEnd  = 0,
	}
	_broadcast("PostureChanged", uid, maxVal, maxVal)
end

--[[
	Put a player into the Stagger state for STAGGER_DURATION seconds.
	Fires the Staggered event; exits back to Idle when duration expires.
	No-ops if already staggered.
]]
function PostureService.TriggerStagger(player: Player)
	local state = _getOrCreate(player)
	if state.Staggered then return end

	local cfg = _getDiscConfig(player)
	local dur = cfg and cfg.StaggerDuration or 0.8

	state.Staggered = true
	state.StaggerEnd = tick() + dur
	state.Current = 0

	-- Track via character attribute so broken-posture can be detected without
	-- locking the player out of blocking/parrying (which would enable infinite combos).
	local character = player.Character
	if character then
		character:SetAttribute("IsStaggered", true)
	end

	-- Broadcast so clients play stagger VFX
	_broadcast("Staggered", player.UserId, STAGGER_DURATION)

	print(("[PostureService] ⚡ %s Staggered for %.1fs"):format(player.Name, STAGGER_DURATION))

	-- Auto-exit Stagger after duration
	task.delay(STAGGER_DURATION, function()
		local stateNow = _postures[player.UserId]
		if not stateNow then return end  -- player left

		stateNow.Staggered = false
		-- Restore a small amount of posture so it's not immediately re-broken
		stateNow.Current = math.floor(stateNow.Max * 0.20)  -- 20% on exit
		_notifyChange(player, stateNow)

		-- Clear stagger attribute
		local exitChar = player.Character
		if exitChar then
			exitChar:SetAttribute("IsStaggered", false)
		end
		print(("[PostureService] %s Stagger expired"):format(player.Name))
	end)
end

--[[
	Check whether a player is currently in the Stagger vulnerability window.
	@return boolean
]]
function PostureService.IsStaggered(player: Player): boolean
	local uid = player.UserId
	local state = _postures[uid]
	if not state then return false end
	return state.Staggered and tick() < state.StaggerEnd
end

--[[
	Execute a Break attack against a Staggered target.
	Only succeeds while the target is actually in the Stagger window.

	@param attacker  The player landing the Break.
	@param target    The Staggered player.
	@return success : boolean
]]
function PostureService.ExecuteBreak(attacker: Player, target: Player, damage: number?): boolean
	-- `damage` is optional; when provided it overrides the default BREAK_DAMAGE
	if not PostureService.IsStaggered(target) then
		warn(("[PostureService] Break attempt failed — %s is not staggered"):format(target.Name))
		return false
	end

	-- Immediately exit stagger so it can't be hit twice
	local state = _getOrCreate(target)
	state.Staggered = false

	local dmg = damage or BREAK_DAMAGE

	-- Apply Break HP damage via CombatService
	if CombatService then
		CombatService.ApplyBreakDamage(target, dmg)
	else
		-- Fallback: directly damage humanoid health
		local character = target.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = math.max(0, humanoid.Health - dmg)
		end
	end

	-- Restore a small amount of posture to the target post-break
	state.Current = math.floor(state.Max * 0.15)
	_notifyChange(target, state)

	-- Clear stagger attribute on the target after a successful Break
	local breakChar = target.Character
	if breakChar then
		breakChar:SetAttribute("IsStaggered", false)
	end

	-- Broadcast Break event
	_broadcast("BreakExecuted", attacker.UserId, target.UserId, dmg)

	print(("[PostureService] 💥 Break! %s → %s (%d HP damage)"):format(
		attacker.Name, target.Name, dmg))
	return true
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function PostureService:Init()
	print("[PostureService] Initializing...")

	-- Set up posture tracking per player
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			PostureService.ResetPosture(player)
		end)
	end)

	-- Handle players already in the server
	for _, player in Players:GetPlayers() do
		PostureService.ResetPosture(player)
		player.CharacterAdded:Connect(function()
			PostureService.ResetPosture(player)
		end)
	end

	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(player)
		_postures[player.UserId] = nil
	end)

	print("[PostureService] Initialized successfully")
end

function PostureService:Start()
	print("[PostureService] Starting...")

	-- Lazy resolve to avoid circular require
	CombatService = require(script.Parent.CombatService)

	-- Passive regen loop (every Heartbeat)
	RunService.Heartbeat:Connect(function(dt: number)
		local now = tick()
		for uid, state in _postures do
			-- Skip staggered players (no regen during stagger)
			if state.Staggered then continue end
			-- Skip if recently hit
			if now - state.LastHitTime < REGEN_PAUSE_WINDOW then continue end
			-- Skip at full posture
			if state.Current >= state.Max then continue end

			-- Determine regen rate (slower while blocking)
			local player = Players:GetPlayerByUserId(uid)
local rate
				local cfg
				if player then
					local playerData = StateService:GetPlayerData(player)
					if playerData then
						cfg = _getDiscConfig(player)
					end
				end
				if cfg then
				rate = cfg.postureRecovery or DEFAULT_REGEN_RATE
			else
				rate = DEFAULT_REGEN_RATE
			end
			if playerData and playerData.State == "Blocking" then
				if cfg and cfg.postureRegenBlocking then
					rate = cfg.postureRegenBlocking
				else
					rate = REGEN_RATE_BLOCKING
				end
			end
			local prev = state.Current
			state.Current = math.min(state.Max, state.Current + rate * dt)

			-- Only network-broadcast on meaningful change (≥0.5 pts)
			if math.abs(state.Current - prev) >= 0.5 and player then
				_notifyChange(player, state)
			end
		end
	end)

	-- Send the local player their current posture after a short delay so the
	-- client's PostureChanged listener is guaranteed to be connected first.
	local function _sendInitialPosture(player: Player)
		task.delay(0.5, function()
			local uid = player.UserId
			local state = _postures[uid]
			if state then
				_fireClient(player, "PostureChanged", uid, state.Current, state.Max)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			_sendInitialPosture(player)
		end)
	end)

	-- Cover players who are already in-game when Start() runs
	for _, player in Players:GetPlayers() do
		_sendInitialPosture(player)
	end

	print("[PostureService] Started successfully")
end

return PostureService
