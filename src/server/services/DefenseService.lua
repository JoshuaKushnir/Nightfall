--!strict
--[[
	DefenseService.lua

	Issue #9: Timing-Based Parry and Block System
	Epic: Phase 2 - Combat & Fluidity

	Server-authoritative defense mechanics. Handles blocking and parrying with
	proper cooldowns, posture drain, and counter-attack opportunities.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateService = require(ReplicatedStorage.Shared.modules.StateService)

local DefenseService = {}

-- Lazy-required to avoid circular deps; resolved in :Start()
local PostureService: any = nil

-- Storage
local PlayerBlocks: {[Player]: {Active: boolean, StartTime: number}} = {}
local ParryWindows: {[Player]: number} = {} -- Track when parry was attempted
local LastBlockTime: {[Player]: number} = {}

-- Constants
local PARRY_WINDOW = 0.2 -- Seconds for parry timing
local BLOCK_COOLDOWN = 0.1 -- Minimum between block activate/release
-- BLOCK_DAMAGE_REDUCTION removed: blocked hits now deal 0 HP (dual-health model #75)
local BLOCK_SPEED_REDUCTION = 0.6 -- 60% movement speed while blocking
-- POSTURE_BLOCK_DRAIN removed: posture drain delegated to PostureService (#75)
local PARRY_STUN_DURATION = 0.5 -- Seconds attacker is stunned

--[[
	Initialize the service
]]
function DefenseService:Init()
	print("[DefenseService] Initializing...")

	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(function(player)
		PlayerBlocks[player] = nil
		ParryWindows[player] = nil
		LastBlockTime[player] = nil
	end)

	print("[DefenseService] Initialized successfully")
end

--[[
	Start the service
]]
function DefenseService:Start()
	print("[DefenseService] Starting...")

	-- Lazy resolve
	PostureService = require(script.Parent.PostureService)

	print("[DefenseService] Started successfully")
end

--[[
	Start a block (player holds block button)
	@param player The player starting block
	@return Success status
]]
function DefenseService.StartBlock(player: Player): boolean
	if not PlayerBlocks[player] then
		PlayerBlocks[player] = {Active = false, StartTime = 0}
	end

	local blockData = PlayerBlocks[player]

	-- Check cooldown
	if LastBlockTime[player] and tick() - LastBlockTime[player] < BLOCK_COOLDOWN then
		return false
	end

	-- Can't block while stunned
	local playerData = StateService:GetPlayerData(player)
	if not playerData or playerData.State == "Stunned" then
		return false
	end

	blockData.Active = true
	blockData.StartTime = tick()
	LastBlockTime[player] = tick()

	-- Update player state
	StateService:SetPlayerState(player, "Blocking")

	-- Slow movement while blocking
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if hum then
		local base = (hum:GetAttribute("BaseWalkSpeed") :: number?) or hum.WalkSpeed
		hum.WalkSpeed = base * BLOCK_SPEED_REDUCTION
	end

	print(`[DefenseService] {player.Name} started blocking`)
	return true
end

--[[
	Release a block
	@param player The player releasing block
]]
function DefenseService.ReleaseBlock(player: Player)
	if not PlayerBlocks[player] then
		return
	end

	local blockData = PlayerBlocks[player]
	blockData.Active = false

	-- Return to Idle or previous state
	local playerData = StateService:GetPlayerData(player)
	if playerData and playerData.State == "Blocking" then
		StateService:SetPlayerState(player, "Idle")
	end

	-- Restore full walk speed
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if hum then
		local base = (hum:GetAttribute("BaseWalkSpeed") :: number?) or 16
		hum.WalkSpeed = base
	end

	print(`[DefenseService] {player.Name} released block`)
end

--[[
	Attempt a parry (requires tight timing)
	@param player The player attempting parry
	@return Success status
]]
function DefenseService.AttemptParry(player: Player): boolean
	-- Record parry attempt time
	ParryWindows[player] = tick()

	print(`[DefenseService] {player.Name} attempted parry`)
	return true
end

--[[
	Check if a parry was successful (called when incoming hit detected)
	@param attacker The attacking player
	@param defender The defending player
	@return Success status (true if parry blocked the hit)
]]
function DefenseService.CheckParryTiming(attacker: Player, defender: Player): boolean
	local parryTime = ParryWindows[defender]

	if not parryTime then
		return false
	end

	local timeSinceParry = tick() - parryTime
	local success = timeSinceParry <= PARRY_WINDOW

	if success then
		print(`[DefenseService] ✓ Parry successful! {defender.Name} parried {attacker.Name}`)

		-- Stun the attacker
		StateService:SetPlayerState(attacker, "Stunned", true)
		task.delay(PARRY_STUN_DURATION, function()
			local attackerData = StateService:GetPlayerData(attacker)
			if attackerData and attackerData.State == "Stunned" then
				StateService:SetPlayerState(attacker, "Idle")
			end
		end)

		-- #157: parrying DRAINS posture (relieves pressure on the defender)
		if PostureService then
			PostureService.DrainPosture(defender, nil, "Parry")
		end

		-- Clear parry window
		ParryWindows[defender] = nil
	else
		print(`[DefenseService] ✗ Parry failed (timing window: {PARRY_WINDOW}s, delay: {timeSinceParry}s)`)
	end

	return success
end

--[[
	Calculate damage reduction for blocked hit
	@param baseDamage The original damage
	@param blocker The blocking player
	@return Reduced damage amount and whether block was successful
]]
function DefenseService.CalculateBlockedDamage(baseDamage: number, blocker: Player): (number, boolean)
	if not PlayerBlocks[blocker] then
		return baseDamage, false
	end

	local blockData = PlayerBlocks[blocker]

	if not blockData.Active then
		return baseDamage, false
	end

	-- Block successful
	local reducedDamage = 0  -- Dual-health model (#75): blocked hits deal 0 HP damage

	if PostureService then
		-- #157: blocking FILLS posture (pressure gauge model)
		local suppressed = PostureService.GainPosture(blocker, nil)
		if suppressed then
			print(`[DefenseService] {blocker.Name}'s posture maxed — Suppressed!`)
		end
	end

	print(`[DefenseService] Block! {blocker.Name} absorbed {baseDamage} damage (0 HP, posture drained)`)
	return reducedDamage, true
end

--[[
	Get block speed reduction multiplier
	@param player The player to check
	@return Speed multiplier (1.0 if not blocking)
]]
function DefenseService.GetBlockSpeedMultiplier(player: Player): number
	if not PlayerBlocks[player] or not PlayerBlocks[player].Active then
		return 1.0
	end

	return BLOCK_SPEED_REDUCTION
end

return DefenseService
