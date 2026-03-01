--!strict
--[[
	AbilitySystem.lua  — Server service
	Issue #72: Weapon abilities — active + passive framework
	Epic #66: Modular Weapon Library & Equip System

	Tracks per-player hit counters for passive-ability triggers and
	handles active-ability activation requests from clients.

	Passive abilities are triggered from CombatService after a confirmed hit
	via AbilitySystem.OnHit(attacker, target, weapon).

	Active abilities are triggered by a client remote event ("UseAbility").
	Server enforces cooldowns; clients cannot bypass them.

	Public API (server):
		AbilitySystem.OnHit(attacker, target, weapon)
		AbilitySystem.HandleUseAbility(player)    -- called by server runtime via NetworkService
		AbilitySystem.GetPassive(weapon)  -> abilityConfig?
		AbilitySystem.GetActive(weapon)   -> abilityConfig?
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponRegistry   = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local AbilityRegistry  = require(ReplicatedStorage.Shared.modules.AbilityRegistry)
local WeaponService    = require(script.Parent.WeaponService)

local AbilitySystem = {}

-- ─── State ────────────────────────────────────────────────────────────────────

-- Hit counter per attacker per target (for TriggerEveryNHits passives)
-- { [attackerUserId]: { [targetName]: hitCount } }
local _hitCounters: {[number]: {[string]: number}} = {}

-- Active ability cooldown end-times per player
-- { [UserId]: { [abilityId]: cooldownEndTime } }
local _activeCooldowns: {[number]: {[string]: number}} = {}

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _GetHitCounter(attacker: Player, targetName: string): number
	local uid = attacker.UserId
	if not _hitCounters[uid] then _hitCounters[uid] = {} end
	return _hitCounters[uid][targetName] or 0
end

local function _IncrementHitCounter(attacker: Player, targetName: string): number
	local uid = attacker.UserId
	if not _hitCounters[uid] then _hitCounters[uid] = {} end
	local count = (_hitCounters[uid][targetName] or 0) + 1
	_hitCounters[uid][targetName] = count
	return count
end

local function _ResetHitCounter(attacker: Player, targetName: string)
	local uid = attacker.UserId
	if _hitCounters[uid] then
		_hitCounters[uid][targetName] = 0
	end
end

local function _IsActiveCoolingDown(player: Player, abilityId: string): boolean
	local uid = player.UserId
	if not _activeCooldowns[uid] then return false end
	local endTime = _activeCooldowns[uid][abilityId]
	return endTime ~= nil and tick() < endTime
end

local function _StartActiveCooldown(player: Player, abilityId: string, cooldown: number)
	local uid = player.UserId
	if not _activeCooldowns[uid] then _activeCooldowns[uid] = {} end
	_activeCooldowns[uid][abilityId] = tick() + cooldown
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Retrieve the passive ability config for a weapon, or nil.
]]
function AbilitySystem.GetPassive(weapon: any): any?
	if not weapon or not weapon.Abilities or not weapon.Abilities.Passive then return nil end
	return AbilityRegistry.Get(weapon.Abilities.Passive)
end

--[[
	Retrieve the active ability config for a weapon, or nil.
]]
function AbilitySystem.GetActive(weapon: any): any?
	if not weapon or not weapon.Abilities or not weapon.Abilities.Active then return nil end
	return AbilityRegistry.Get(weapon.Abilities.Active)
end

--[[
	Call this from CombatService after every confirmed hit.
	Increments the per-target hit counter and fires passive OnTrigger
	when the threshold (TriggerEveryNHits) is reached.

	@param attacker   The attacking player
	@param target     The hit instance (Player or dummy Model)
	@param weapon     WeaponConfig for the weapon used
]]
function AbilitySystem.OnHit(attacker: Player, target: any, weapon: any)
	if not attacker or not target or not weapon then return end

	local passive = AbilitySystem.GetPassive(weapon)
	if not passive or passive.Type ~= "Passive" then return end

	local targetName: string
	if typeof(target) == "Instance" and target:IsA("Player") then
		targetName = (target :: Player).Name
	elseif typeof(target) == "Instance" and target:IsA("Model") then
		targetName = target.Name
	else
		return
	end

	local threshold = passive.TriggerEveryNHits or 3
	local count = _IncrementHitCounter(attacker, targetName)

	if count >= threshold then
		_ResetHitCounter(attacker, targetName)
		if passive.OnTrigger then
			local ok, err = pcall(passive.OnTrigger, attacker, target, weapon)
			if not ok then
				warn(("[AbilitySystem] Passive '%s' OnTrigger error: %s"):format(passive.Id, tostring(err)))
			end
		end
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function AbilitySystem:Init()
	print("[AbilitySystem] Initializing...")

	Players.PlayerRemoving:Connect(function(player)
		_hitCounters[player.UserId]    = nil
		_activeCooldowns[player.UserId] = nil
	end)

	print("[AbilitySystem] Initialized successfully")
end

--[[
	Handle a UseAbility request from a client. Called by the server runtime
	via NetworkService:RegisterHandler so that rate-limiting middleware applies.
]]
function AbilitySystem.HandleUseAbility(player: Player)
	-- Look up this player's equipped weapon
	local weaponId = WeaponService.GetEquipped(player)
	if not weaponId then
		print(("[AbilitySystem] UseAbility from %s — no weapon equipped"):format(player.Name))
		return
	end

	local weapon = WeaponRegistry.Get(weaponId)
	if not weapon then return end

	local active = AbilitySystem.GetActive(weapon)
	if not active then
		-- Fists and other weapons without an active ability: silently ignore
		print(("[AbilitySystem] %s: weapon '%s' has no active ability"):format(player.Name, weaponId))
		return
	end

	if _IsActiveCoolingDown(player, active.Id) then
		print(("[AbilitySystem] %s UseAbility cooldown not ready: %s"):format(player.Name, active.Id))
		return
	end

	-- Start cooldown before activation (prevents double-fire)
	_StartActiveCooldown(player, active.Id, active.Cooldown or 8)

	if active.OnActivate then
		local ok, err = pcall(active.OnActivate, player, weapon)
		if not ok then
			warn(("[AbilitySystem] Active '%s' OnActivate error: %s"):format(active.Id, tostring(err)))
		else
			print(("[AbilitySystem] ✓ %s activated %s"):format(player.Name, active.Id))
		end
	end
end

--[[
	HandleUseAbilityById — activate a standalone ability by Id directly.
	Used by InventoryService for AbilityItem category items.
	Enforces cooldowns server-side, independent of weapon state.

	@param player     The activating player
	@param abilityId  Ability Id matching a registered module in shared/abilities
]]
function AbilitySystem.HandleUseAbilityById(player: Player, abilityId: string)
	if not player or not abilityId then return end

	local ability = AbilityRegistry.Get(abilityId)
	if not ability then
		warn(("[AbilitySystem] HandleUseAbilityById: unknown ability '%s'"):format(abilityId))
		return
	end

	if ability.Type ~= "Active" then
		print(("[AbilitySystem] '%s' is not an Active ability (type: %s)"):format(abilityId, ability.Type))
		return
	end

	if _IsActiveCoolingDown(player, abilityId) then
		print(("[AbilitySystem] %s: '%s' still cooling down"):format(player.Name, abilityId))
		return
	end

	_StartActiveCooldown(player, abilityId, ability.Cooldown or 8)

	if ability.OnActivate then
		local ok, err = pcall(ability.OnActivate, player, nil)  -- no weapon context
		if not ok then
			warn(("[AbilitySystem] '%s' OnActivate error: %s"):format(abilityId, tostring(err)))
		else
			print(("[AbilitySystem] ✓ %s activated %s"):format(player.Name, abilityId))
		end
	end
end

function AbilitySystem:Start()
	print("[AbilitySystem] Started successfully")
end

return AbilitySystem
