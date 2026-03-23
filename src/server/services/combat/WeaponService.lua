--!strict
--[[
	WeaponService.lua

	Issue #69: Weapon Equip System
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Server-side handler for weapon equip/unequip.
	Validates player state, looks up weapons via WeaponRegistry, stores the
	equipped weapon id per-player, and broadcasts changes to all clients.

	Public API:
		WeaponService.GetEquipped(player) -> string?

	CHANGES from original:
	- _EquipDefault: gives fists Tool to Backpack only, does NOT call EquipWeapon.
	  Player spawns unarmed. They must drag fists to the hotbar and click to hold.
	- EquipWeapon: removed "already equipped" guard. Now does a proper swap —
	  sheathe current weapon first (Character → Backpack), then hold new one.
	- UnequipWeapon: no longer calls _RemoveTool (which destroyed the tool forever).
	  Now sheathes by moving Tool Character → Backpack. Tool stays, re-equippable.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkProvider  = require(ReplicatedStorage.Shared.network.NetworkProvider)
local WeaponRegistry   = require(ReplicatedStorage.Shared.modules.combat.WeaponRegistry)
local StateService     = require(ReplicatedStorage.Shared.modules.core.StateService)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.progression.DisciplineConfig)

local WeaponService = {}

-- ─── Injected dependencies ───────────────────────────────────────────────────
-- Populated in Init(); DataService is the authoritative source for player stats.
local _DataService: any = nil

-- ─── Storage ─────────────────────────────────────────────────────────────────

-- Keyed by player UserId; value is the weapon Id currently HELD (in Character).
-- nil means unarmed (tool may still be in Backpack).
local EquippedWeapons: {[number]: string} = {}

-- ─── Anti-cheat (#74) ────────────────────────────────────────────────────────

local _lastAttackTime: {[number]: number} = {}
local _strikes: {[number]: number} = {}
-- track last violation timestamp so we can decay the strike count after a window
local _lastViolationTime: {[number]: number} = {}
local VIOLATION_DECAY_TIME = 1.5 -- seconds until strikes reset

-- minimum interval between *swing attempts*; hits from a multi‑target attack
-- or AoE will no longer trigger violations because we count once per action
local SERVER_ATTACK_COOLDOWN    = 0.08  -- raised from 0.05 to tolerate fast combos
local SERVER_RANGE_TOLERANCE    = 3
local MAX_DAMAGE_MULTIPLIER     = 2.0
-- allow more infractions before kicking; the counter now decays over time
local MAX_VIOLATIONS_BEFORE_KICK = 6

-- ─── Constants ───────────────────────────────────────────────────────────────

local EQUIP_EVENT_NAME     = "EquipWeapon"
local UNEQUIP_EVENT_NAME   = "UnequipWeapon"
local EQUIPPED_BROADCAST   = "WeaponEquipped"
local UNEQUIPPED_BROADCAST = "WeaponUnequipped"
local EQUIP_RESULT_EVENT   = "WeaponEquipResult"

local ATTR_EQUIPPED = "EquippedWeapon"

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function _GiveTool(player: Player, config: any)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		warn(`[WeaponService] No Backpack found for {player.Name} — cannot give tool`)
		return
	end

	-- Remove any leftover tool with the same weapon id first (safety).
	for _, item in backpack:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("WeaponId") == config.Id then
			item:Destroy()
		end
	end

	local tool = Instance.new("Tool")
	tool.Name           = config.Name
	tool.ToolTip        = config.Description or ""
	tool.RequiresHandle = false
	tool.CanBeDropped   = false
	tool:SetAttribute("WeaponId", config.Id)

	if config.GripOffset then
		tool.GripPos     = config.GripOffset.Position
		tool.GripRight   = config.GripOffset.RightVector
		tool.GripUp      = config.GripOffset.UpVector
		tool.GripForward = config.GripOffset.LookVector
	end

	tool.Parent = backpack
	print(`[WeaponService] ✓ Tool '{tool.Name}' added to {player.Name}'s Backpack`)
end

-- Sheathe: move Tool from Character back to Backpack. Does NOT destroy it.
local function _SheatheTool(player: Player, weaponId: string)
	local char = player.Character
	local bp   = player:FindFirstChildOfClass("Backpack")
	if char and bp then
		for _, item in char:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
				item.Parent = bp
				return
			end
		end
	end
end

--[[
	Check proficiency when a player equips a weapon.
	Returns whether cross-training is active and the applicable penalty multipliers
	from DisciplineConfig.crossTrainPenalty.

	If the player's computed DisciplineId covers the weapon's WeightClass → full proficiency.
	If not → cross-train penalty multipliers apply.
	Returns (isCrossTrain, hpMult, postureMult, speedMult, breathMult).
]]
local function _getProficiency(player: Player, config: any): (boolean, number, number, number, number)
	-- Full proficiency: weapon has no WeightClass restriction
	if not config.WeightClass then
		return false, 1.0, 1.0, 1.0, 1.0
	end

	-- Fists always allow without penalty (baseline weapon)
	if config.Id == "fists" then
		return false, 1.0, 1.0, 1.0, 1.0
	end

	-- Try to read player's computed DisciplineId from DataService
	if not _DataService then
		-- DataService not available — allow without penalty (safe fallback)
		return false, 1.0, 1.0, 1.0, 1.0
	end

	local profile = _DataService:GetProfile(player)
	if not profile then
		return false, 1.0, 1.0, 1.0, 1.0
	end

	local disciplineId: string = profile.DisciplineId or "Wayward"
	local discCfg = DisciplineConfig.Get(disciplineId)

	if not discCfg or not discCfg.weaponClasses then
		return false, 1.0, 1.0, 1.0, 1.0
	end

	-- Check if weapon's weight class is in the discipline's allowed list
	if table.find(discCfg.weaponClasses, config.WeightClass) then
		return false, 1.0, 1.0, 1.0, 1.0
	end

	-- Cross-training: apply the global cross-train penalty from DisciplineConfig
	local penalty = DisciplineConfig.Raw and DisciplineConfig.Raw.crossTrainPenalty
		or { hpDamageMult = 0.85, postureDamageMult = 0.9, attackSpeedMult = 0.95, breathCostMult = 1.15 }

	local hp     = penalty.hpDamageMult     or 0.85
	local pos    = penalty.postureDamageMult or 0.90
	local speed  = penalty.attackSpeedMult  or 0.95
	local breath = penalty.breathCostMult   or 1.15

	warn((`[WeaponService] {player.Name} cross-training: equipping {config.WeightClass} weapon "{config.Id}" `
		.. `as {disciplineId} (allowed: {table.concat(discCfg.weaponClasses, ", ")})`)
		.. (" — penalties: hp=%.0f%% pos=%.0f%% spd=%.0f%% breath=%.0f%%"):format(
			hp*100, pos*100, speed*100, breath*100))

	return true, hp, pos, speed, breath
end

-- Apply or clear proficiency penalty attributes on a Tool
local function _applyProficiencyAttributes(tool: Tool, isCross: boolean, hp: number, pos: number, speed: number, breath: number)
	tool:SetAttribute("CrossTraining",     isCross)
	tool:SetAttribute("ProfHpDamageMult",  hp)
	tool:SetAttribute("ProfPostureMult",   pos)
	tool:SetAttribute("ProfSpeedMult",     speed)
	tool:SetAttribute("ProfBreathMult",    breath)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function WeaponService.RecordViolation(player: Player, reason: string)
	local uid = player.UserId
	local now = tick()
	-- decay old strikes after a short grace period
	if _lastViolationTime[uid] and now - _lastViolationTime[uid] > VIOLATION_DECAY_TIME then
		_strikes[uid] = 0
	end
	_lastViolationTime[uid] = now
	
	_strikes[uid] = (_strikes[uid] or 0) + 1
	warn(("[WeaponService] ⚠  Strike %d/%d for %s — %s"):format(
		_strikes[uid], MAX_VIOLATIONS_BEFORE_KICK, player.Name, reason))
	if _strikes[uid] >= MAX_VIOLATIONS_BEFORE_KICK then
		player:Kick("Anti-cheat: excessive violation count.")
	end
end

function WeaponService.ValidateAttack(player: Player, hitData: any): (boolean, number)
	local uid     = player.UserId
	local now     = tick()
	local last    = _lastAttackTime[uid] or 0
	if now - last < SERVER_ATTACK_COOLDOWN then
		WeaponService.RecordViolation(player, "attack too fast")
		return false, 0
	end
	_lastAttackTime[uid] = now

	local weaponId = EquippedWeapons[uid]
	if not weaponId then return false, 0 end
	local config = WeaponRegistry.Get(weaponId)
	if not config then return false, 0 end

	local damage = hitData and hitData.Damage or 0
	local cap    = config.BaseDamage * MAX_DAMAGE_MULTIPLIER
	if damage > cap then
		WeaponService.RecordViolation(player, "damage over cap")
		damage = cap
	end

	return true, damage
end

function WeaponService.GetEquipped(player: Player): string?
	return EquippedWeapons[player.UserId]
end

-- ─── Attack Pipeline (#171) ──────────────────────────────────────────────────

-- Lazy-required to avoid circular dependency chains at module load time
local _CombatService: any = nil
local _HitboxService: any = nil

local function _requireCombatService()
	if not _CombatService then _CombatService = require(script.Parent.CombatService) end
	return _CombatService
end

local function _requireHitboxService()
	if not _HitboxService then _HitboxService = require(ReplicatedStorage.Shared.modules.combat.HitboxService) end
	return _HitboxService
end

-- Minimum gate between server-processed swings (100 ms) — distinct from ValidateAttack's 50 ms fast-path
local MIN_SWING_INTERVAL = 0.10

--[[
	HandleAttackRequest
	Full server-side pipeline for WeaponAttackRequest packets (after packet-shape
	validation in the runtime handler). Steps:
		1. Rate-limit gate (100 ms per player)
		2. Weapon-id match via GetEquipped()
		3. Timestamp sanity (3 s clock-skew tolerance)
		4. State guard (Dead / Stunned / Ragdolled → reject)
		5. Hitbox built from weapon.Range / weapon.BaseDamage
		6. CombatService.ValidateHit inside OnHit callback
		7. AttackResult reply fired to client
]]
function WeaponService.HandleAttackRequest(player: Player, packet: any)
	local CombatService = _requireCombatService()
	local HitboxService = _requireHitboxService()

	local uid = player.UserId
	local now = tick()

	-- 1. Rate-limit gate
	local lastSwing = _lastAttackTime[uid] or 0
	if now - lastSwing < MIN_SWING_INTERVAL then
		return
	end
	_lastAttackTime[uid] = now

	-- 2. Weapon-id match
	local equippedId = WeaponService.GetEquipped(player)
	if equippedId ~= packet.WeaponId then
		WeaponService.RecordViolation(player, "weapon id mismatch")
		return
	end

	-- 3. Timestamp sanity — reject packets older than 3 s
	if now - packet.ClientTime > 3 then
		warn(("[WeaponService] Stale packet from %s (age=%.1fs)"):format(player.Name, now - packet.ClientTime))
		return
	end

	-- 4. State guard
	local playerData = StateService:GetPlayerData(player)
	if not playerData then return end
	local pState = playerData.State
	if pState == "Dead" or pState == "Stunned" or pState == "Ragdolled" then
		return
	end

	-- 5. Weapon config lookup
	local weapon = WeaponRegistry.Get(packet.WeaponId)
	if not weapon then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local range: number = (weapon :: any).Range or 7
	local aimData: any = packet.AimData
	local aimPos: Vector3
	if aimData and aimData.Origin and aimData.Direction then
		aimPos = aimData.Origin + aimData.Direction * (range * 0.5)
	else
		aimPos = root.Position + root.CFrame.LookVector * (range * 0.5)
	end

	local baseDamage: number = (weapon :: any).BaseDamage or 10
	local postureDamage: number
	if packet.AttackType == "Heavy" and (weapon :: any).HeavyPostureDamage then
		postureDamage = (weapon :: any).HeavyPostureDamage
	elseif (weapon :: any).PostureDamage then
		postureDamage = (weapon :: any).PostureDamage
	else
		postureDamage = baseDamage
	end

	-- 6. Hitbox — apply damage on first valid contact
	local hitHappened = false
	local hitbox = HitboxService.CreateHitbox({
		Owner    = player,
		Shape    = "Box",
		Position = aimPos,
		Size     = Vector3.new(range, range, range),
		Damage   = baseDamage,
		LifeTime = 0.1,
		OnHit    = function(target: any, _hd: any)
			if hitHappened then return end
			hitHappened = true
			local targetName: string? = nil
			if typeof(target) == "Instance" and target:IsA("Player") then
				targetName = (target :: Player).Name
			elseif type(target) == "string" then
				targetName = target
			end
			if not targetName then
				hitHappened = false
				return
			end
			CombatService.ValidateHit(player, {
				TargetName             = targetName,
				Damage                 = baseDamage,
				PostureDamage          = postureDamage,
				HitType                = "Weapon",
				WeaponId               = packet.WeaponId,
				BypassWeaponValidation = true,
				BypassRateLimit        = true,
			})
		end,
	})
	HitboxService.TestHitbox(hitbox)

	-- 7. Reply with swing result
	local resultEvent = NetworkProvider:GetRemoteEvent("AttackResult")
	if resultEvent then
		resultEvent:FireClient(player, {
			WeaponId      = packet.WeaponId,
			AttackType    = packet.AttackType,
			SequenceIndex = packet.SequenceIndex,
			Hit           = hitHappened,
		})
	end
end

--[[
	Equip (hold/draw) a weapon for a player.
	If the player is already holding a different weapon, sheathe it first.
	The tool must already be in the player's Backpack (given by _EquipDefault
	or a previous equip). If it's missing, _GiveTool is called to create it.
]]
function WeaponService.EquipWeapon(player: Player, weaponId: string)
	local humanoid = _GetHumanoid(player)
	if not humanoid then
		warn(`[WeaponService] Equip denied for {player.Name} — no character/humanoid`)
		return
	end
	if humanoid.Health <= 0 then
		warn(`[WeaponService] Equip denied for {player.Name} — player is dead`)
		return
	end

	if not WeaponRegistry.Has(weaponId) then
		warn(`[WeaponService] Unknown weapon id "{weaponId}" requested by {player.Name}`)
		return
	end

	local current = EquippedWeapons[player.UserId]

	-- Already holding the same weapon — no-op
	if current == weaponId then return end

	-- Sheathe current weapon first (move Character → Backpack, don't destroy)
	if current then
		_SheatheTool(player, current)
		EquippedWeapons[player.UserId] = nil
		if player.Character then
			player.Character:SetAttribute(ATTR_EQUIPPED, nil)
		end
	end

	-- Discipline cross-training check (#133: proficiency system)
	local config = WeaponRegistry.Get(weaponId)
	local isCross, hpMult, posMult, speedMult, breathMult = _getProficiency(player, config)

	-- Apply penalty attributes to whichever tool is being equipped
	-- (We do this after the tool is placed in Character / Backpack below)

	-- Store as held
	EquippedWeapons[player.UserId] = weaponId
	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, weaponId)
	end

	-- Move Tool Backpack → Character to physically hold it.
	-- If the tool doesn't exist yet in the backpack, create it first.
	local bp   = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	local toolFound = false

	if bp then
		for _, item in bp:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
				if char then item.Parent = char end
				toolFound = true
				break
			end
		end
	end

	if not toolFound then
		if config then _GiveTool(player, config) end
		-- _GiveTool parents to Backpack; now move to Character
		local bp2 = player:FindFirstChildOfClass("Backpack")
		if bp2 and char then
			for _, item in bp2:GetChildren() do
				if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
					item.Parent = char
					break
				end
			end
		end
	end

	print(`[WeaponService] ✓ {player.Name} equipped "{weaponId}"`)

	-- Apply proficiency attributes to the tool now that it's in the character
	local char2 = player.Character
	if char2 then
		for _, item in char2:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
				_applyProficiencyAttributes(item :: Tool, isCross, hpMult, posMult, speedMult, breathMult)
				break
			end
		end
	end

	-- Broadcast that weapon is equipped to all clients
	local equippedEvent = NetworkProvider:GetRemoteEvent(EQUIPPED_BROADCAST)
	if equippedEvent then
		equippedEvent:FireAllClients(player, weaponId)
	end

	-- Notify the equipping player of the result + proficiency status
	local resultEvent = NetworkProvider:GetRemoteEvent(EQUIP_RESULT_EVENT)
	if resultEvent then
		resultEvent:FireClient(player, {
			Success          = true,
			WeaponId         = weaponId,
			IsCrossTraining  = isCross,
			HpDamageMult     = hpMult,
			PostureDamageMult = posMult,
			AttackSpeedMult  = speedMult,
			BreathCostMult   = breathMult,
		})
	end
end

--[[
	Unequip (sheathe) the current weapon for a player.
	Moves the Tool Character → Backpack. Does NOT destroy it.
]]
function WeaponService.UnequipWeapon(player: Player)
	local current = EquippedWeapons[player.UserId]
	if not current then return end

	EquippedWeapons[player.UserId] = nil

	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, nil)
	end

	-- Sheathe: move Tool back to Backpack, keep it alive
	_SheatheTool(player, current)

	print(`[WeaponService] ✓ {player.Name} sheathed "{current}"`)

	local unequippedEvent = NetworkProvider:GetRemoteEvent(UNEQUIPPED_BROADCAST)
	if unequippedEvent then
		unequippedEvent:FireAllClients(player)
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

--[[
	Give the player their fists tool on spawn.
	Does NOT call EquipWeapon — player spawns UNARMED.
	EquippedWeapons stays nil so the first EquipWeapon call from the hotbar works.
]]
local function _EquipDefault(player: Player)
	-- Clear any stale held state from a previous life
	EquippedWeapons[player.UserId] = nil
	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, nil)
	end

	-- Wait for Humanoid (CharacterAdded fires before children are ready)
	if player.Character then
		player.Character:WaitForChild("Humanoid", 10)
	end

	-- Give fists Tool to Backpack so it's available to equip from the hotbar
	local config = WeaponRegistry.Get("fists")
	if config then
		_GiveTool(player, config)
	end
end

function WeaponService:Init(dependencies: any)
	print("[WeaponService] Initializing...")

	if dependencies then
		_DataService = dependencies.DataService or nil
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(_character)
			task.spawn(_EquipDefault, player)
		end)
		if player.Character then
			task.spawn(_EquipDefault, player)
		end
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(_character)
			task.spawn(_EquipDefault, player)
		end)
		if player.Character then
			task.spawn(_EquipDefault, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		EquippedWeapons[player.UserId]    = nil
		_lastAttackTime[player.UserId]    = nil
		_strikes[player.UserId]           = nil
	end)

	print("[WeaponService] Initialized successfully")
end

function WeaponService:Start()
	print("[WeaponService] Starting...")

	local equipEvent = NetworkProvider:GetRemoteEvent(EQUIP_EVENT_NAME)
	if equipEvent then
		equipEvent.OnServerEvent:Connect(function(player, weaponId)
			if typeof(weaponId) ~= "string" then
				warn(`[WeaponService] EquipWeapon from {player.Name} — invalid weaponId type`)
				return
			end
			WeaponService.EquipWeapon(player, weaponId)
		end)
	end

	local unequipEvent = NetworkProvider:GetRemoteEvent(UNEQUIP_EVENT_NAME)
	if unequipEvent then
		unequipEvent.OnServerEvent:Connect(function(player)
			WeaponService.UnequipWeapon(player)
		end)
	end

	print("[WeaponService] Started successfully")
end

return WeaponService