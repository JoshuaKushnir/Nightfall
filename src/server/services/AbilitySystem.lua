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

local WeaponRegistry: any = nil
local AbilityRegistry: any = nil
local WeaponService: any = nil
local AbilityValidator: any = nil
local EffectRunner: any = nil
local PassiveSystem: any = nil

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
	local endTime = tick() + cooldown
	_activeCooldowns[uid][abilityId] = endTime

	-- Sync to character attribute for client UI reflection
	local char = player.Character
	if char then
		char:SetAttribute("CD_" .. abilityId, endTime)
	end
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

function AbilitySystem:Init(dependencies: any?)
	print("[AbilitySystem] Initializing...")

	WeaponRegistry   = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
	AbilityRegistry  = require(ReplicatedStorage.Shared.modules.AbilityRegistry)
	AbilityValidator = require(script.Parent.AbilityValidator)

	if dependencies then
		WeaponService = dependencies.WeaponService
		EffectRunner = dependencies.EffectRunner
		PassiveSystem = dependencies.PassiveSystem
	else
		WeaponService = require(script.Parent.WeaponService)
		EffectRunner = require(script.Parent.EffectRunner)
		PassiveSystem = require(script.Parent.PassiveSystem)
	end

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
        print(("[AbilitySystem] %s: weapon '%s' has no active ability"):format(player.Name, weaponId))
        return
    end

    -- ── Centralised validation ────────────────────────────────────────────────
    local ok, reason, context = AbilityValidator.ValidateUse(player, active)
    if not ok then
        print(("[AbilitySystem] %s ValidateUse failed: %s (%s)")
            :format(player.Name, active.Id, tostring(reason)))
        return
    end

    -- ── Cooldown (start before activation to prevent double-fire) ─────────────
    _StartActiveCooldown(player, active.Id, active.Cooldown or 8)

    -- ── Execute: data-driven effects first, then OnActivate fallback ──────────
    if active.effects and type(active.effects) == "table" and #active.effects > 0 then
        -- Build EffectContext from validator context
        local eventCtx = {
            casterId        = player.UserId,
            casterPlayer    = player,
            abilityId       = active.Id,
            castOrigin      = (context :: any).castOrigin,
            castTargetPoint = (context :: any).castTargetPoint,
        }
        -- No hitCtx at cast time — individual effects supply hitCtx when a hit is confirmed.
        -- Self-targeting effects (Heal, SelfBuff) receive nil hitCtx and handle it internally.
        for _, effectDef in active.effects do
            local runOk, runErr = pcall(EffectRunner.Run, EffectRunner, effectDef, eventCtx, nil, PassiveSystem)
            if not runOk then
                warn(("[AbilitySystem] EffectRunner.Run error for '%s': %s")
                    :format(active.Id, tostring(runErr)))
            end
        end
        print(("[AbilitySystem] ✓ %s activated %s (data-driven, %d effects)")
            :format(player.Name, active.Id, #active.effects))
    end

    -- Always run OnActivate if present — handles movement/VFX logic that cannot
    -- be expressed as declarative EffectDef tables (dashes, afterimages, etc.)
    if active.OnActivate then
        local pcallOk, pcallErr = pcall(active.OnActivate, player, weapon)
        if not pcallOk then
            warn(("[AbilitySystem] Active '%s' OnActivate error: %s")
                :format(active.Id, tostring(pcallErr)))
        elseif not (active.effects and #active.effects > 0) then
            -- Only print the activation line once (above already printed if effects ran)
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

--[[
	HandleExpressionAbility — activate a Depth-1 Expression ability with target position.
	Called by AspectService when AbilityRegistry resolves an Expression-type ability.
	Enforces cooldowns server-side.  Passes targetPosition to OnActivate so spatial
	effects (dash direction, target seek radius, etc.) work correctly.

	Issue #123–127: Depth-1 Expression abilities (Ash / Tide / Ember / Gale / Void)

	@param player        The activating player
	@param abilityId     Ability Id ("AshenStep", "Current", "Ignite", "WindStrike", "Blink")
	@param targetPos     Optional Vector3 sent by the client as a cast direction / aim hint
]]
function AbilitySystem.HandleExpressionAbility(
	player: Player,
	abilityId: string,
	targetPos: Vector3?
)
	if not player or not abilityId then return end

	local ability = AbilityRegistry.Get(abilityId)
	if not ability then
		warn(("[AbilitySystem] HandleExpressionAbility: unknown ability '%s'"):format(abilityId))
		return
	end

	if ability.Type ~= "Expression" then
		warn(("[AbilitySystem] '%s' is not an Expression ability (type: %s)"):format(
			abilityId, ability.Type))
		return
	end

	if _IsActiveCoolingDown(player, abilityId) then
		print(("[AbilitySystem] %s: '%s' still cooling down"):format(player.Name, abilityId))
		return
	end

	-- ManaCost deduction is handled upstream by AspectService; here we only own cooldowns
	_StartActiveCooldown(player, abilityId, ability.Cooldown or 6)

	if ability.OnActivate then
		local ok, err = pcall(ability.OnActivate, player, targetPos)
		if not ok then
			warn(("[AbilitySystem] Expression '%s' OnActivate error: %s"):format(
				abilityId, tostring(err)))
		else
			print(("[AbilitySystem] ✓ %s cast Expression ability %s"):format(player.Name, abilityId))
		end
	end
end

function AbilitySystem:Start()
	print("[AbilitySystem] Started successfully")
end

return AbilitySystem
