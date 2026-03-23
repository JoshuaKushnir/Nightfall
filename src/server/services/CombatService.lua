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
local RunService = game:GetService("RunService")   -- #199: module scope, not per-Start()

local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local DummyService = require(script.Parent.DummyService)

-- Lazy-required to avoid load-order cycles; resolved in :Start()
local AbilitySystem: any = nil
local WeaponService: any = nil
local PostureService: any = nil
local ProgressionService: any = nil
local HollowedService: any = nil
local StateSyncService: any = nil
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)

-- Constants needed by helpers
local BREAK_HIT_DAMAGE = 45   -- HP damage dealt on a successful Break (mirrors PostureService.BREAK_DAMAGE)

local CombatService = {}

-- helper: determine if attacker is using a weapon outside their primary discipline
local function _isCrossTrained(player: Player): boolean
	if not player then return false end
	local data = StateService:GetPlayerData(player)
	if not data then return false end
	local discCfg = DisciplineConfig.Get(data.DisciplineId)
	if not discCfg or not discCfg.weaponClasses then return false end
	local weaponId = WeaponService and WeaponService.GetEquipped(player)
	if not weaponId then return false end
	local wcfg = WeaponRegistry.Get(weaponId)
	if not wcfg or not wcfg.WeightClass then return false end
	return not table.find(discCfg.weaponClasses, wcfg.WeightClass)
end

-- calculate Break damage given overflow posture amount (or 0)
function CombatService.CalculateBreakDamage(attacker: Player, overflow: number): number
	overflow = overflow or 0
	local base = BREAK_HIT_DAMAGE
	local mult = 1.0
	local data = attacker and StateService:GetPlayerData(attacker)
	if data then
		local cfg = DisciplineConfig.Get(data.DisciplineId)
		if cfg then
			base = cfg.breakBase or base
			mult = cfg.breakOverflowMult or mult
		end
	end
	local dmg = base + overflow * mult
	if _isCrossTrained(attacker) then
		local pen = DisciplineConfig.crossTrainPenalty and DisciplineConfig.crossTrainPenalty.hpDamageMult
		if pen and pen < 1 then
			dmg = dmg * pen
		end
	end
	return math.floor(dmg)
end

-- Rate limiting per player (prevent spam)
local HitCooldowns: {[Player]: number} = {}
local HIT_COOLDOWN_MIN = 0.05 -- Minimum 50ms between hits per player

-- Constants
local BASE_DAMAGE_VARIANCE = 0.1 -- ±10% damage variance
local CRITICAL_CHANCE = 0.15 -- 15% critical hit chance
local CRITICAL_MULTIPLIER = 1.5 -- 1.5x damage on crit
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
	AbilitySystem     = require(script.Parent.AbilitySystem)
	WeaponService     = require(script.Parent.WeaponService)
	PostureService    = require(script.Parent.PostureService)
	ProgressionService = require(script.Parent.ProgressionService)
	HollowedService   = require(script.Parent.HollowedService)
	StateSyncService  = require(script.Parent.StateSyncService)

	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg)
			if msg:sub(1, 10) == "/debug hp " then
				local val = tonumber(msg:sub(11))
				if val then
					local pd = StateService:GetPlayerData(player)
					if pd then
						pd.Health.Current = math.max(0, pd.Health.Current - val)
						if StateSyncService then StateSyncService.SendCombatUpdate(player) end
						print(`[CombatService Debug] Took {val} damage`)
					end
				end
			elseif msg:sub(1, 15) == "/debug posture " then
				local val = tonumber(msg:sub(16))
				if val and PostureService then
					PostureService.GainPosture(player, val)
					print(`[CombatService Debug] Gained {val} posture`)
				end
			elseif msg == "/debug sync" then
				if StateSyncService then
					StateSyncService.SyncPlayer(player)
					print(`[CombatService Debug] Forced state sync`)
				end
			end
		end)
	end)

	-- #199: RunService already required at module scope
	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			if player.Character then
				CombatService._ProcessDamageAttributes(player.Character, player.Name)
			end
		end
		if DummyService.GetAllDummies then
			for _, dummyData in DummyService.GetAllDummies() do
				local model = DummyService.GetDummyModel(dummyData.Id)
				if model then
					CombatService._ProcessDamageAttributes(model, dummyData.Id)
				end
			end
		end
		if HollowedService and HollowedService.GetAllInstances then
			for id, _ in HollowedService.GetAllInstances() do
				local model = workspace:FindFirstChild(id)
				if model then
					CombatService._ProcessDamageAttributes(model, id)
				end
			end
		end
	end)

	-- This service is event-driven. Events are received via NetworkProvider
	-- in the server runtime. This Start is here for consistency with other services.

	print("[CombatService] Started successfully")
end

--[[
	Reads attribute damage placed by abilities ("IncomingHPDamage") and executes correctly
]]
function CombatService._ProcessDamageAttributes(character: Model, targetName: string)
	local hpVal = (character:GetAttribute("IncomingHPDamage") or 0) :: number
	local postVal = (character:GetAttribute("IncomingPostureDamage") or 0) :: number

	if hpVal <= 0 and postVal <= 0 then return end

	local hpSource = (character:GetAttribute("IncomingHPDamageSource") or "Unknown") :: string
	local postSource = (character:GetAttribute("IncomingPostureDamageSource") or "Unknown") :: string

	-- Clear attributes
	character:SetAttribute("IncomingHPDamage", 0)
	character:SetAttribute("IncomingPostureDamage", 0)

	local sourceStr = (hpVal > 0) and hpSource or postSource
	-- #190: string.match avoids table allocation vs string.split
	local attackerName = string.match(sourceStr, "^([^_]+)") or "Unknown"
	local attacker = Players:FindFirstChild(attackerName)

	if attacker then
		-- Process via ValidateHit (which handles block/dodge states)
		local hitData = {
			TargetName = targetName,
			Damage = hpVal,
			PostureDamage = postVal,
			HitType = "Ability",
			BypassRateLimit = true,
			BypassWeaponValidation = true,
			BypassPosture = false -- Let ValidateHit handle the posture logic properly
		}
		CombatService.ValidateHit(attacker, hitData)
	else
		-- Fallback to applying damage directly if attacker left (or is an NPC)
		local targetPlayer = Players:FindFirstChild(targetName)
		if targetPlayer then
			if postVal > 0 and PostureService then
				PostureService.GainPosture(targetPlayer, postVal)

				local targetData = StateService:GetPlayerData(targetPlayer)
				if targetData and targetData.State == "Blocking" then
					local blockEvent = NetworkProvider:GetRemoteEvent(BLOCK_FEEDBACK_EVENT_NAME)
					if blockEvent then
						blockEvent:FireClient(targetPlayer, attacker, hpVal)
					end

					local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT_NAME)
					if hitEvent then
						hitEvent:FireAllClients(attacker, targetPlayer, 0, false, false, "Crouching", nil, 0.25)
					end
				end
			end

			if hpVal > 0 then
				local pd = StateService:GetPlayerData(targetPlayer)
				if pd then
					pd.Health.Current = math.max(0, pd.Health.Current - hpVal)
					if StateSyncService then StateSyncService.SendCombatUpdate(targetPlayer) end

					if pd.Health.Current <= 0 then
						StateService:SetPlayerState(targetPlayer, "Dead")
						print(`[CombatService] ☠️  {targetPlayer.Name} defeated! ({hpVal} damage)`)
					end

					local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT_NAME)
					if hitEvent then
						hitEvent:FireAllClients(nil, targetPlayer, hpVal, false, false)
					end
				end
			end
		elseif DummyService.GetDummyData(targetName) then
			if hpVal > 0 then
				local attackerPos: Vector3? = nil
				if sourceStr then
					local sourceId = string.gsub(sourceStr, "_Attack$", "")
					local npcModel = workspace:FindFirstChild(sourceId)
					if npcModel and npcModel.PrimaryPart then
						attackerPos = npcModel.PrimaryPart.Position
					end
				end
				DummyService.ApplyDamage(targetName, hpVal, attackerPos)
				local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT_NAME)
				if hitEvent then
					hitEvent:FireAllClients(nil, targetName, hpVal, false, true)
				end
			end
		elseif HollowedService and HollowedService.GetInstanceData(targetName) then
			HollowedService.ApplyDamage(targetName, hpVal, attacker, postVal)
			if hpVal > 0 then
				local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT_NAME)
				if hitEvent then
					hitEvent:FireAllClients(nil, targetName, hpVal, false, true)
				end
			end
		end
	end
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

	-- Rate limiting (skipped for server-initiated ability hits)
	if hitData.BypassRateLimit ~= true then
		local now = tick()
		if HitCooldowns[attacker] and now - HitCooldowns[attacker] < HIT_COOLDOWN_MIN then
			print(`[CombatService] ✗ Hit spam cooldown: {attacker.Name}`)
			return false, 0
		end
		HitCooldowns[attacker] = now
	end

	-- Anti-cheat: weapon range and damage ceiling (#74)
	-- Skipped for server-initiated ability hits (BypassWeaponValidation = true)
	if WeaponService and hitData.BypassWeaponValidation ~= true then
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

	-- Find target (player or dummy or hollowed enemy)
	local targetPlayer = Players:FindFirstChild(targetName)
	local targetDummy  = nil
	local isDummy      = false
	local isHollowed   = false

	if targetPlayer and Utils.IsValidPlayer(targetPlayer) then
		-- Target is a player
		-- (no local `target` variable needed)
	elseif DummyService.GetDummyData(targetName) then
		-- Target is a training dummy
		targetDummy = DummyService.GetDummyData(targetName)
		isDummy = true
	elseif HollowedService and HollowedService.GetInstanceData(targetName) then
		-- Target is a Hollowed enemy NPC
		isHollowed = true
	else
		print(`[CombatService] ✗ Target not found: {targetName}`)
		return false, 0
	end

	-- Can't hit self (only for players)
	if not isDummy and not isHollowed and attacker == targetPlayer then
		print("[CombatService] ✗ Self-hit attempted")
		return false, 0
	end

	-- Get target data
	local targetData = nil
	if isDummy then
		targetData = targetDummy
	elseif isHollowed then
		-- Hollowed instances do not use the PlayerData struct;
		-- damage is dispatched via HollowedService.ApplyDamage below.
		targetData = HollowedService.GetInstanceData(targetName)
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

		-- Sliding targets: harder to guardbreak — reduce posture damage by 50% (#171)
		if targetData.State == "Sliding" and hitData.PostureDamage then
			hitData = table.clone(hitData)
			hitData.PostureDamage = math.floor((hitData.PostureDamage :: number) * 0.5)
			print(`[CombatService] Slide modifier: posture damage halved for {targetPlayer.Name}`)
		end

		-- WallRunning targets: TODO — increased hitstun when wall-run is implemented (#171)
	end

	-- Apply damage with variance
	local finalDamage = CombatService._ApplyDamageVariance(baseDamage)
	local isCritical = CombatService._RollCritical()

	-- Apply active-ability damage reduction (IronWill etc.)
	do
		local targetChar: Model? = nil
		if not isDummy and not isHollowed and targetPlayer then
			targetChar = (targetPlayer :: Player).Character
		end
		if targetChar then
			local reduction = targetChar:GetAttribute("DamageReduction")
			if type(reduction) == "number" and reduction > 0 then
				finalDamage = math.floor(finalDamage * (1 - reduction))
				print(("[CombatService] DamageReduction %.0f%% applied → %d"):format(reduction * 100, finalDamage))
			end
			-- Apply DamageTaken multiplier (BloodRage drawback on target)
			local damageTaken = targetChar:GetAttribute("DamageTaken")
			if type(damageTaken) == "number" and damageTaken ~= 1 then
				finalDamage = math.floor(finalDamage * damageTaken)
				print(("[CombatService] DamageTaken x%.2f applied (BloodRage) → %d"):format(damageTaken, finalDamage))
			end
		end
	end

	-- Apply attacker's active damage boost (Adrenaline etc.) OR penalty (Weakened)
	do
		local attackerChar = attacker.Character
		if attackerChar then
			local boost = attackerChar:GetAttribute("DamageBoost")
			if type(boost) == "number" and boost ~= 1 then
				-- boost > 1: damage increase; boost < 1: Weakened damage penalty
				finalDamage = math.floor(finalDamage * boost)
				local label = boost > 1 and "DamageBoost" or "Weakened"
				print(("[CombatService] %s x%.2f applied (%s) → %d"):format(label, boost, label, finalDamage))
			end
		end
	end

	if isCritical then
		finalDamage = math.floor(finalDamage * CRITICAL_MULTIPLIER)
		print(`[CombatService] ⚡ CRITICAL HIT: {baseDamage} → {finalDamage}`)
	else
		finalDamage = math.floor(finalDamage)
	end

	-- apply cross-training penalty if attacker is using off-discipline weapon
	if _isCrossTrained(attacker) then
		local pen = DisciplineConfig.crossTrainPenalty and DisciplineConfig.crossTrainPenalty.hpDamageMult
		if pen and pen < 1 then
			finalDamage = math.floor(finalDamage * pen)
			print(`[CombatService] ⚠ Cross-train penalty applied, damage -> {finalDamage}`)
		end
	end

	-- Check defense (block/parry) - only for players
	local wasBlocked = false
	local wasParried = false

	if not isDummy and not isHollowed then
		local isBlockBreaker = hitData.HitType == "Heavy" or hitData.AttackType == "Heavy" or (hitData.PostureDamage and hitData.PostureDamage >= 40)

		-- Server-side block check
		if targetData.State == "Blocking" and not isBlockBreaker then
			-- Blocked hits drain Posture but deal NO HP damage (dual-health model #75)
			wasBlocked = true
			finalDamage = 0
			print(`[CombatService] 🛡️  Blocked — filling posture instead of HP`)

			-- #157: blocking FILLS posture pressure (GainPosture)
			if PostureService and not hitData.BypassPosture then
				local suppressed = PostureService.GainPosture(targetPlayer, hitData.PostureDamage)
				if suppressed then
					print(`[CombatService] 🔒 {targetPlayer.Name} Suppressed — posture maxed!`)
				end
			end

			-- Notify target of block feedback
			local blockEvent = NetworkProvider:GetRemoteEvent(BLOCK_FEEDBACK_EVENT_NAME)
			if blockEvent then
				blockEvent:FireClient(targetPlayer, attacker, baseDamage)
			end
		elseif isBlockBreaker then
			-- Block breaking attacks force Suppressed state regardless of block
			print(`[CombatService] 💥 Block-breaking attack landed on {targetPlayer.Name}!`)
			if PostureService then
				PostureService.TriggerSuppressed(targetPlayer)
			end
		end
	end

	-- Apply damage to target
	if finalDamage > 0 then
		if isDummy then
			-- Apply damage to dummy. Only send the attacker's position if this hit
			-- should produce knockback (finisher hits); regular swings do not push.
			local attackerPos: Vector3? = nil
			if hitData.IsFinisher and attacker and attacker.Character then
				local root = attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then attackerPos = root.Position end
			end
			local stillAlive = DummyService.ApplyDamage(targetName, finalDamage, attackerPos)
			if not stillAlive then
				print(`[CombatService] ☠️ Dummy defeated! ({finalDamage} damage)`)
			else
				print(`[CombatService] ✓ Hit confirmed: {attacker.Name} → Dummy {targetName} ({finalDamage} damage)`)
			end
		elseif isHollowed then
			-- Dispatch to HollowedService; it handles health, death, and Resonance grant.
			local stillAlive = HollowedService.ApplyDamage(targetName, finalDamage, attacker, hitData.PostureDamage)
			if not stillAlive then
				print(`[CombatService] ☠️ Hollowed defeated! ({finalDamage} damage)`)
			else
				print(`[CombatService] ✓ Hit confirmed: {attacker.Name} → {targetName} ({finalDamage} damage)`)
			end
		else


			-- Normal HP hit
			targetData.Health.Current = math.max(0, targetData.Health.Current - finalDamage)
			if StateSyncService and targetPlayer then StateSyncService.SendCombatUpdate(targetPlayer) end

			-- Check if target died
			if targetData.Health.Current <= 0 then
				StateService:SetPlayerState(targetPlayer, "Dead")
				print(`[CombatService] ☠️  {targetPlayer.Name} defeated! ({finalDamage} damage)`)
				-- Grant Resonance to the killer (Issue #138)
				if ProgressionService then
					local source = if isDummy then "Kill_Dummy" else "Kill_Player"
					ProgressionService.GrantResonance(attacker, ProgressionService.RESONANCE_GRANTS[source] or 10, source)
				end
			else
				print(`[CombatService] ✓ Hit confirmed: {attacker.Name} → {targetPlayer.Name} ({finalDamage} damage)`)
			end
		end

		-- Broadcast hit confirmation to all clients
		local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT_NAME)
		if hitEvent then
			if isDummy or isHollowed then
				-- For NPCs, fire to all clients (no reaction animation)
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
				local abilityTarget = (isDummy or isHollowed)
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

	playerData.Health.Current = math.max(0, playerData.Health.Current - amount)
	print(('[CombatService] 💥 Break damage: %s lost %d HP (now %d)'):format(
		player.Name, amount, playerData.Health.Current))

	if playerData.Health.Current <= 0 then
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

	local maxHealth = playerData.Health.Max
	playerData.Health.Current = math.min(maxHealth, playerData.Health.Current + amount)

	print(`[CombatService] ✓ {player.Name} healed: +{amount} HP (now {playerData.Health.Current}/{maxHealth})`)

	return playerData.Health.Current
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

	local maxPosture = playerData.Posture.Max
	playerData.Posture.Current = math.min(maxPosture, playerData.Posture.Current + amount)

	print(`[CombatService] ✓ {player.Name} posture restored: +{amount} (now {playerData.Posture.Current}/{maxPosture})`)

	return playerData.Posture.Current
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

--[[
	ValidateAoEHit — server-initiated multi-target hit batch.
	Wraps ValidateHit in a loop with rate-limit and weapon-validation bypassed
	because this path is driven by the server AspectService, not client spam.

	@param attacker   The casting player.
	@param hitResults Array of {TargetName: string, Damage: number, HitType: string?}
	@return           Map of TargetName -> {Success: boolean, Damage: number}
]]
function CombatService.ValidateAoEHit(
	attacker: Player?,
	hitResults: {{TargetName: string, Damage: number, HitType: string?}}
): {[string]: {Success: boolean, Damage: number}}
	local results: {[string]: {Success: boolean, Damage: number}} = {}
	if not attacker or not Utils.IsValidPlayer(attacker) then
		warn("[CombatService] ValidateAoEHit: invalid attacker")
		return results
	end
	for _, hit in ipairs(hitResults) do
		if type(hit.TargetName) ~= "string" or type(hit.Damage) ~= "number" then
			warn("[CombatService] ValidateAoEHit: malformed entry, skipping")
			continue
		end
		local hitData: {[string]: any} = {
			TargetName             = hit.TargetName,
			Damage                 = hit.Damage,
			HitType                = hit.HitType or "Ability",
			BypassRateLimit        = true,  -- server-initiated, no spam risk
			BypassWeaponValidation = true,  -- ability damage, not weapon-sourced
		}
		local success, damage = CombatService.ValidateHit(attacker, hitData)
		results[hit.TargetName] = {Success = success, Damage = damage}
	end
	return results
end

return CombatService
