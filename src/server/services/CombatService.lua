--!strict
--[[
	CombatService.lua
	
	Issue #28: Modular Hitbox System - Server Validation
	Epic: Phase 2 - Combat & Fluidity
	
	Server-authoritative hit validation and damage application.
	Receives hit events from client, validates against DefenseService,
	applies damage, and broadcasts feedback to all clients.
	
	Dependencies: StateService, DefenseService, NetworkProvider, Utils
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local DummyService = require(script.Parent.DummyService)

-- Lazy-required to avoid load-order cycles; resolved in :Start()
local AbilitySystem: any = nil
local WeaponService: any = nil
local PostureService: any = nil
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

local CombatService = {}

-- Rate limiting per player (prevent spam)
local HitCooldowns: {[Player]: number} = {}
local HIT_COOLDOWN_MIN = 0.05 -- Minimum 50ms between hits per player

-- Constants
local BASE_DAMAGE_VARIANCE = 0.1 -- ±10% damage variance
local CRITICAL_CHANCE = 0.15 -- 15% critical hit chance
local CRITICAL_MULTIPLIER = 1.5 -- 1.5x damage on crit
local BREAK_HIT_DAMAGE = 45   -- HP damage dealt on a successful Break (mirrors PostureService.BREAK_DAMAGE)
local CONFIRM_HIT_EVENT_NAME = "HitConfirmed"
local BLOCK_FEEDBACK_EVENT_NAME = "BlockFeedback"
local PARRY_FEEDBACK_EVENT_NAME = "ParryFeedback"

--[[
	Initialize the service
]]
function CombatService:Init()
	print("[CombatService] Initializing...")
	
	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(player)
		HitCooldowns[player] = nil
	end)
	
	print("[CombatService] Initialized successfully")
end

--[[
	Start the service
]]
function CombatService:Start()
	print("[CombatService] Starting...")
	
	-- Resolve lazy dependencies (avoids circular-require at module load time)
	AbilitySystem = require(script.Parent.AbilitySystem)
	WeaponService  = require(script.Parent.WeaponService)
	PostureService = require(script.Parent.PostureService)
	
	-- This service is event-driven. Events are received via NetworkProvider
	-- in the server runtime. This Start is here for consistency with other services.
	
	print("[CombatService] Started successfully")
end

--[[
	Handle a hit request from client (ActionController)
	Called by server runtime when receiving hit events
	
	@param attacker The attacking player
	@param hitData Data about the hit (target position, damage type, etc)
	@return HitResult with confirmed damage and whether hit succeeded
]]
function CombatService.ValidateHit(attacker: Player?, hitData: {[string]: any}?): (boolean, number)
	if not attacker or not Utils.IsValidPlayer(attacker) then
		print("[CombatService] ✗ Invalid attacker")
		return false, 0
	end
	
	if not hitData then
		print("[CombatService] ✗ No hit data")
		return false, 0
	end
	
	-- Rate limiting
	local now = tick()
	if HitCooldowns[attacker] and now - HitCooldowns[attacker] < HIT_COOLDOWN_MIN then
		print(`[CombatService] ✗ Hit spam cooldown: {attacker.Name}`)
		return false, 0
	end
	HitCooldowns[attacker] = now

	-- Anti-cheat: rate, range and damage ceiling (#74)
	if WeaponService then
		local ok, clampedDamage = WeaponService.ValidateAttack(attacker, hitData)
		if not ok then
			print(`[CombatService] ✗ Anti-cheat blocked hit from {attacker.Name}`)
			return false, 0
		end
		-- Use the server-clamped damage value from here on
		hitData = table.clone(hitData)
		hitData.Damage = clampedDamage
	end
	
	-- Get attacker data
	local attackerData = StateService:GetPlayerData(attacker)
	if not attackerData or attackerData.State == "Stunned" then
		print(`[CombatService] ✗ Attacker invalid state: {attackerData and attackerData.State or "nil"}`)
		return false, 0
	end
	
	-- Extract hit info from data
	local targetName: string? = hitData.TargetName
	local baseDamage: number = hitData.Damage or 10
	local hitType: string = hitData.HitType or "Attack"
	
	if not targetName then
		print("[CombatService] ✗ No target name in hit data")
		return false, 0
	end
	
	-- Find target (player or dummy)
	local targetPlayer = Players:FindFirstChild(targetName)
	local targetDummy = nil
	local isDummy = false
	
	if targetPlayer and Utils.IsValidPlayer(targetPlayer) then
		-- Target is a player
		target = targetPlayer
	elseif DummyService.GetDummyData(targetName) then
		-- Target is a dummy
		targetDummy = DummyService.GetDummyData(targetName)
		isDummy = true
	else
		print(`[CombatService] ✗ Target not found: {targetName}`)
		return false, 0
	end
	
	-- Can't hit self (only for players)
	if not isDummy and attacker == targetPlayer then
		print("[CombatService] ✗ Self-hit attempted")
		return false, 0
	end
	
	-- Get target data
	local targetData = nil
	if isDummy then
		targetData = targetDummy
	else
		targetData = StateService:GetPlayerData(targetPlayer)
		if not targetData then
			print(`[CombatService] ✗ Target data not found: {targetPlayer.Name}`)
			return false, 0
		end
		
		-- Check if target is dodging (iframes)
		if targetData.State == "Dodging" then
			print(`[CombatService] ✗ Target is dodging (iframes): {targetPlayer.Name}`)
			return false, 0
		end
	end
	
	-- Apply damage with variance
	local finalDamage = CombatService._ApplyDamageVariance(baseDamage)
	local isCritical = CombatService._RollCritical()

	-- Apply active-ability damage reduction (IronWill etc.)
	do
		local targetChar: Model? = nil
		if not isDummy and targetPlayer then
			targetChar = (targetPlayer :: Player).Character
		end
		if targetChar then
			local reduction = targetChar:GetAttribute("DamageReduction")
			if type(reduction) == "number" and reduction > 0 then
				finalDamage = math.floor(finalDamage * (1 - reduction))
				print(("[CombatService] DamageReduction %.0f%% applied → %d"):format(reduction * 100, finalDamage))
			end
		end
	end

	-- Apply attacker's active damage boost (Adrenaline etc.)
	do
		local attackerChar = attacker.Character
		if attackerChar then
			local boost = attackerChar:GetAttribute("DamageBoost")
			if type(boost) == "number" and boost > 1 then
				finalDamage = math.floor(finalDamage * boost)
				print(("[CombatService] DamageBoost x%.2f applied → %d"):format(boost, finalDamage))
			end
		end
	end
	
	if isCritical then
		finalDamage = math.floor(finalDamage * CRITICAL_MULTIPLIER)
		print(`[CombatService] ⚡ CRITICAL HIT: {baseDamage} → {finalDamage}`)
	else
		finalDamage = math.floor(finalDamage)
	end
	
	-- Check defense (block/parry) - only for players
	local wasBlocked = false
	local wasParried = false
	
	if not isDummy then
		-- Server-side block check
		if targetData.State == "Blocking" then
			-- Blocked hits drain Posture but deal NO HP damage (dual-health model #75)
			wasBlocked = true
			finalDamage = 0
			print(`[CombatService] 🛡️  Blocked — draining posture instead of HP`)

			-- Drain posture on the blocker
			if PostureService then
				local broke = PostureService.DrainPosture(targetPlayer, nil, "Blocked")
				if broke then
					print(`[CombatService] ⚡ {targetPlayer.Name}'s posture broken by blocked hit!`)
				end
			end

			-- Notify target of block feedback
			local blockEvent = NetworkProvider:GetRemoteEvent(BLOCK_FEEDBACK_EVENT_NAME)
			if blockEvent then
				blockEvent:FireClient(targetPlayer, attacker, baseDamage)
			end
		end
	end
	
	-- Apply damage to target
	if finalDamage > 0 then
		if isDummy then
			-- Apply damage to dummy (pass attacker position for knockback)
			local attackerPos: Vector3? = nil
			if attacker and attacker.Character then
				local root = attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then attackerPos = root.Position end
			end
			local stillAlive = DummyService.ApplyDamage(targetName, finalDamage, attackerPos)
			if not stillAlive then
				print(`[CombatService] ☠️ Dummy defeated! ({finalDamage} damage)`)
			else
				print(`[CombatService] ✓ Hit confirmed: {attacker.Name} → Dummy {targetName} ({finalDamage} damage)`)
			end
		else
			-- Dual-health model (#75): unguarded hits drain both HP and Posture.
			-- (Blocked hits already returned 0 finalDamage above so this block is
			-- only reached for unblocked / unguarded hits.)

			-- Check for Break opportunity — if target is in PostureService Stagger window,
			-- execute a Break instead of a normal hit (more damage, special event).
			if PostureService and PostureService.IsStaggered(targetPlayer) then
				local success = PostureService.ExecuteBreak(attacker, targetPlayer)
				if success then
					print(`[CombatService] 💥 Break executed on {targetPlayer.Name}`)
					-- Break handled posture + HP, so skip normal damage below
					return true, BREAK_HIT_DAMAGE
				end
			end

			targetData.Health = math.max(0, targetData.Health - finalDamage)

			-- Drain posture from unguarded hit
			if PostureService then
				local broke = PostureService.DrainPosture(targetPlayer, nil, "Unguarded")
				if broke then
					print(`[CombatService] ⚡ {targetPlayer.Name}'s posture broken by unguarded hit!`)
				end
			end

			-- Check if target died
			if targetData.Health <= 0 then
				StateService:SetPlayerState(targetPlayer, "Dead")
				print(`[CombatService] ☠️  {targetPlayer.Name} defeated! ({finalDamage} damage)`)
			else
				print(`[CombatService] ✓ Hit confirmed: {attacker.Name} → {targetPlayer.Name} ({finalDamage} damage)`)
			end
		end
		
		-- Broadcast hit confirmation to all clients
		local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT_NAME)
		if hitEvent then
			if isDummy then
				-- For dummies, fire to all clients (no reaction animation)
				hitEvent:FireAllClients(attacker, targetName, finalDamage, isCritical, true)
			else
				-- For players, include optional reaction animation info when blocked
				local animationName: string? = nil
				local animationAssetName: string? = nil
				local animationDuration: number? = nil
				if wasBlocked then
					animationName = "Crouching"
					animationDuration = 0.25
				end
				-- Fire with an extra param for animation info (clients may ignore if unused)
				hitEvent:FireAllClients(attacker, targetPlayer, finalDamage, isCritical, false, animationName, animationAssetName, animationDuration)
			end
		end

		-- Notify AbilitySystem for passive ability triggers (e.g. Stagger every N hits)
		if AbilitySystem then
			local weaponId = WeaponService and WeaponService.GetEquipped(attacker)
			local weapon = weaponId and WeaponRegistry.Get(weaponId)
			if weapon then
				local abilityTarget = isDummy
					and DummyService.GetDummyModel and DummyService.GetDummyModel(targetName)
					or targetPlayer
				if abilityTarget then
					AbilitySystem.OnHit(attacker, abilityTarget, weapon)
				end
			end
		end

		return true, finalDamage
	end
	
	return false, 0
end

--[[
	Apply damage variance (±10%)
	@param baseDamage Base damage amount
	@return Varied damage
]]
function CombatService._ApplyDamageVariance(baseDamage: number): number
	local variance = baseDamage * BASE_DAMAGE_VARIANCE
	local minDamage = baseDamage - variance
	local maxDamage = baseDamage + variance
	
	return math.random(math.floor(minDamage), math.ceil(maxDamage))
end

--[[
	Roll for critical hit
	@return True if critical
]]
function CombatService._RollCritical(): boolean
	return math.random() < CRITICAL_CHANCE
end

--[[
	Apply Break damage directly to a player's HP (called by PostureService.ExecuteBreak).
	This bypasses normal hit validation — the Stagger check in PostureService is the guard.
	@param player  The Staggered player receiving break damage.
	@param amount  HP damage to apply.
]]
function CombatService.ApplyBreakDamage(player: Player, amount: number)
	local playerData = StateService:GetPlayerData(player)
	if not playerData then return end

	playerData.Health = math.max(0, playerData.Health - amount)
	print(("[CombatService] 💥 Break damage: %s lost %d HP (now %d)"):format(
		player.Name, amount, playerData.Health))

	if playerData.Health <= 0 then
		StateService:SetPlayerState(player, "Dead")
	end
end

--[[
	Heal a player
	@param player The player to heal
	@param amount Healing amount
	@return New health value
]]
function CombatService.HealPlayer(player: Player?, amount: number): number
	if not player or not Utils.IsValidPlayer(player) then
		return 0
	end
	
	local playerData = StateService:GetPlayerData(player)
	if not playerData then
		return 0
	end
	
	local maxHealth = 100 -- Should come from playerData config
	playerData.Health = math.min(maxHealth, playerData.Health + amount)
	
	print(`[CombatService] ✓ {player.Name} healed: +{amount} HP (now {playerData.Health}/{maxHealth})`)
	
	return playerData.Health
end

--[[
	Restore posture (internal resource)
	@param player The player
	@param amount Amount to restore
	@return New posture value
]]
function CombatService.RestorePosture(player: Player?, amount: number): number
	if not player or not Utils.IsValidPlayer(player) then
		return 0
	end
	
	local playerData = StateService:GetPlayerData(player)
	if not playerData then
		return 0
	end
	
	local maxPosture = 100 -- Should come from playerData config
	playerData.PostureHealth = math.min(maxPosture, playerData.PostureHealth + amount)
	
	print(`[CombatService] ✓ {player.Name} posture restored: +{amount} (now {playerData.PostureHealth}/{maxPosture})`)
	
	return playerData.PostureHealth
end

--[[
	Reset cooldowns for a player (on respawn, etc)
	@param player The player
]]
function CombatService.ResetCooldowns(player: Player?)
	if not player then
		return
	end
	
	HitCooldowns[player] = nil
	print(`[CombatService] Cooldowns reset for {player.Name}`)
end

return CombatService
