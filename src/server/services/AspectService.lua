--!strict
--[[
    AspectService.lua

    Issue #12: Server-side logic for Aspect System operations
    Epic: Phase 3 - Mantra / Aspect System

    Authority for assigning aspects, investing shards, casting abilities,
    managing cooldowns and passives. Interacts with DataService, StateService,
    CombatService, and AspectRegistry.

    Dependencies: DataService, StateService, CombatService, NetworkProvider,
                  AspectRegistry, Utils
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- DataService is a sibling module under Server.services; load via relative path
local DataService = require(script.Parent.DataService)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local CombatService = require(script.Parent.CombatService)
local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local NetworkService = require(script.Parent.NetworkService)
local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)
local AbilityRegistry = require(ReplicatedStorage.Shared.modules.AbilityRegistry)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)

-- AbilitySystem required after module definition to avoid circular requires
local AbilitySystem: any = nil
local function _requireAbilitySystem()
    if not AbilitySystem then
        AbilitySystem = require(script.Parent.AbilitySystem)
    end
    return AbilitySystem
end

-- InventoryService lazy-required to break circular dependency
-- (InventoryService → AspectService.ExecuteAbility at its top level)
local _InventoryService: any = nil
local function _requireInventoryService()
    if not _InventoryService then
        _InventoryService = require(script.Parent.InventoryService)
    end
    return _InventoryService
end

-- Forward declarations for functions defined later but called earlier
local _clearPassives: (player: Player) -> ()

local _activePassives = {} :: {[Player]: {[string]: number}} -- passiveId -> depthApplied

-- Type aliases
local AspectTypes = require(ReplicatedStorage.Shared.types.AspectTypes)

-- Cooldown tracking is stored on PlayerData.ActiveCooldowns and mana regen
-- occurs via Heartbeat connection with respect to ManaComponent.RegenDelay.
-- Internal cooldown tracking will live on player data
-- Mana regeneration loop implemented in this service

-- Constants
local MAX_CAST_RANGE           = 50   -- max studs from caster to targetPosition (Issue 3)
local ABILITY_HIT_RADIUS       = 8    -- default sphere radius (studs) when Range not set on ability
local ABILITY_HITBOX_LIFETIME  = 0.15 -- seconds hitbox persists before auto-expiry

local AspectService = {}
AspectService._initialized = false

-- At top of AspectService
local function _getAbility(abilityId: string)
    -- Prefer new registry, fall back to legacy
    local ability = AbilityRegistry.Get(abilityId) or AspectRegistry.Abilities[abilityId]
    if not ability then return nil end

    -- Optionally normalize shape so all fields exist
    ability.Cooldown = ability.Cooldown or 5
    ability.ManaCost = ability.ManaCost or 0
    ability.IsAoE = ability.IsAoE == true
    ability.Range = ability.Range or ABILITY_HIT_RADIUS

    return ability
end


-- helper to fetch aspect data table from player profile
local function _getAspectData(player: Player): AspectTypes.PlayerAspectData?
    local profile = DataService:GetProfile(player)
    if not profile then return nil end
    return profile.AspectData
end

--[[
    GetPlayerAspectData(player) -> PlayerAspectData?
]]
function AspectService.GetPlayerAspectData(player: Player)
    return _getAspectData(player)
end

--[[
    AssignAspect(player, aspectId)
    Only allowed if player has no aspect yet and aspect isn't locked.
    Updates profile and fires network event to client.
]]
function AspectService.AssignAspect(player: Player, aspectId: AspectTypes.AspectId): boolean
    if not Utils.IsValidPlayer(player) then return false end
    local profile = DataService:GetProfile(player)
    if not profile then return false end
    if profile.AspectData then
        warn("[AspectService] Player already has aspect")
        return false
    end
    local cfg = AspectRegistry.GetAspect(aspectId)
    if not cfg or cfg.IsLocked then
        warn("[AspectService] Attempt to assign invalid or locked aspect: "..tostring(aspectId))
        return false
    end
    profile.AspectData = {
        AspectId = aspectId,
        IsUnlocked = true,
        Branches = {
            Expression = {Depth = 0, ShardsInvested = 0},
            Form = {Depth = 0, ShardsInvested = 0},
            Communion = {Depth = 0, ShardsInvested = 0},
        },
        TotalShardsInvested = 0,
    }
    NetworkProvider:FireClient(player, "AspectAssigned", aspectId)
    return true
end

--[[
    DebugSetAspect(player, aspectId)
    Developer-only helper that force-assigns the given aspect and maxes
    all branches to depth 3 so the player has the full moveset. Does not
    perform normal validation (overwrites existing aspect state).
    Returns true on success.
]]
function AspectService.DebugSetAspect(player: Player, aspectId: AspectTypes.AspectId): boolean
    if not Utils.IsValidPlayer(player) then
        return false
    end
    local profile = DataService:GetProfile(player)
    if not profile then
        return false
    end
    local cfg = AspectRegistry.GetAspect(aspectId)
    if not cfg then
        warn("[AspectService] DebugSetAspect invalid aspect: "..tostring(aspectId))
        return false
    end

    profile.AspectData = {
        AspectId = aspectId,
        IsUnlocked = true,
        Branches = {
            Expression = {Depth = 3, ShardsInvested = 500},
            Form       = {Depth = 3, ShardsInvested = 500},
            Communion  = {Depth = 3, ShardsInvested = 500},
        },
        TotalShardsInvested = 1500,
    }
    profile.ResonanceShards = profile.ResonanceShards or 0

    _requireInventoryService().ClearAspectMoves(player, true)
    _requireInventoryService().GrantAspectMoves(player, aspectId)

    AspectService.ApplyPassives(player)
    NetworkProvider:FireClient(player, "AspectAssigned", aspectId)
    NetworkProvider:FireClient(player, "SwitchAspectResult", {
        Success = true,
        AspectId = aspectId
    })
    return true
end

--[[
    SwitchAspect(player, aspectId)
    Switch the player's active Aspect in real time.

    aspectId = nil  → clear Aspect, restore base Ability items
    aspectId = str  → equip that Aspect, replace inventory with its moves

    Validation order:
      1. player exists
      2. not dead / stunned / ragdolled
      3. if aspectId given: aspect exists in registry and is not locked
      4. same aspect already active → early-out (no-op)

    Side effects:
      • profile.AspectData updated (or nilled)
      • InventoryService.ClearAspectMoves called
      • InventoryService.GrantAspectMoves OR RestoreBaseItems called
      • passives applied / removed
      • AspectAssigned + SwitchAspectResult fired to client
]]

local function _clearPassives(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.AspectData then return end

    local passives = AspectRegistry.GetPassivesForAspect(profile.AspectData.AspectId)
    for _, passive in ipairs(passives) do
        if passive.RemoveEffect then
            passive.RemoveEffect(player)
        end
    end
    _activePassives[player] = nil
end

function AspectService.SwitchAspect(player: Player, aspectId: AspectTypes.AspectId?): (boolean, string?)
    if not Utils.IsValidPlayer(player) then
        return false, "InvalidPlayer"
    end

    local profile = DataService:GetProfile(player)
    if not profile then
        return false, "NoProfile"
    end

    -- State gate: cannot switch mid-combat
    local success, state = pcall(function()
        return StateService:GetState(player)
    end)
    if not success then
        state = "Idle" -- fallback if service not ready
    end
    
    if state == "Dead" or state == "Stunned" or state == "Ragdolled" then
        return false, "BadState"
    end

    -- Validate the requested aspect (skip if clearing)
    if aspectId ~= nil then
        local cfg = AspectRegistry.GetAspect(aspectId)
        if not cfg then
            return false, "UnknownAspect"
        end
        if cfg.IsLocked then
            return false, "AspectLocked"
        end
        -- No-op: already on this aspect
        if profile.AspectData and profile.AspectData.AspectId == aspectId then
            return true, nil
        end
    else
        -- No-op: already has no aspect
        if not profile.AspectData then
            return true, nil
        end
    end

    -- ── Remove existing passives before we change AspectData ────────────
    _clearPassives(player)

    local aspects = profile.Aspects or {}
    profile.Aspects = aspects

    if aspectId == nil then
        profile.ActiveAspectId = nil
        _requireInventoryService().RestoreBaseItems(player, true)
    else
        if not aspects[aspectId] then
            aspects[aspectId] = {
                AspectId = aspectId,
                IsUnlocked = true,
                Branches = {
                    Expression = {Depth = 0, ShardsInvested = 0},
                    Form       = {Depth = 0, ShardsInvested = 0},
                    Communion  = {Depth = 0, ShardsInvested = 0},
                },
                TotalShardsInvested = 0,
            }
        end
        profile.ActiveAspectId = aspectId
        profile.AspectData = aspects[aspectId] -- keep existing access path for now

        _requireInventoryService().GrantAspectMoves(player, aspectId, true)
        AspectService.ApplyPassives(player)
    end

    _requireInventoryService().SyncInventory(player)

    -- ── Notify client ────────────────────────────────────────────────────
    NetworkProvider:FireClient(player, "AspectAssigned", aspectId) -- existing event reused
    NetworkService:SendToClient(player, "SwitchAspectResult", {
        Success  = true,
        Reason   = nil,
        AspectId = aspectId,  -- nil signals "no aspect"
    })

    print(("[AspectService] %s switched aspect to: %s"):format(
        player.Name, tostring(aspectId or "nil")))

    return true, nil
end

--[[
    InvestInBranch(player, aspectId, branch, amount) -> (boolean, string?)
    Spend Resonance Shards to deepen a branch. Validates finances, aspect,
    and max depth.
]]
function AspectService.InvestInBranch(player: Player, aspectId: AspectTypes.AspectId, branch: AspectTypes.BranchId, amount: number)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.AspectData then
        return false, "NoAspect"
    end
    if profile.AspectData.AspectId ~= aspectId then
        return false, "WrongAspect"
    end
    -- cost model (spec-gap placeholder values)
    local costs = {100, 250, 500}
    local branchState = profile.AspectData.Branches[branch]
    if not branchState then
        return false, "InvalidBranch"
    end
    if branchState.Depth >= 3 then
        return false, "MaxDepth"
    end
    if amount < 1 then
        return false, "InvalidAmount"
    end
    local newDepth = math.min(3, branchState.Depth + amount)
    local requiredShardTotal = costs[newDepth]
    if profile.ResonanceShards < requiredShardTotal then
        return false, "InsufficientShards"
    end
    profile.ResonanceShards -= requiredShardTotal
    branchState.Depth = newDepth
    branchState.ShardsInvested = branchState.ShardsInvested + requiredShardTotal
    profile.AspectData.TotalShardsInvested += requiredShardTotal

    -- reapply passive effects now that depth changed
    AspectService.ApplyPassives(player)

    return true
end

--[[
    GetUnlockedAbilities(player) -> {AspectAbility}
]]
function AspectService.GetUnlockedAbilities(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.AspectData then return {} end
    local aspectId = profile.AspectData.AspectId
    local abilities = AspectRegistry.GetAbilitiesForAspect(aspectId)
    local unlocked = {}
    for _, ability in ipairs(abilities) do
        local depth = profile.AspectData.Branches[ability.Branch].Depth
        if depth >= ability.MinDepth then
            table.insert(unlocked, ability)
        end
    end
    return unlocked
end

--[[
    ApplyPassives(player)
    Iterate form passives and call ApplyEffect for those unlocked.
    Should also remove any effects not granted anymore. Simplest: clear all then reapply.
]]
local function _getPassiveState(player: Player)
    _activePassives[player] = _activePassives[player] or {}
    return _activePassives[player]
end

function AspectService.ApplyPassives(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.AspectData then return end

    local passives = AspectRegistry.GetPassivesForAspect(profile.AspectData.AspectId)
    local state = _getPassiveState(player)

    for _, passive in ipairs(passives) do
        local currentDepth = profile.AspectData.Branches[passive.Branch].Depth
        local prevDepth = state[passive.Id] or 0
        local unlockedNow = currentDepth >= passive.MinDepth
        local unlockedBefore = prevDepth >= passive.MinDepth

        if unlockedBefore and not unlockedNow then
            if passive.RemoveEffect then
                passive.RemoveEffect(player)
            end
            state[passive.Id] = currentDepth
        elseif not unlockedBefore and unlockedNow then
            if passive.ApplyEffect then
                passive.ApplyEffect(player, profile)
            end
            state[passive.Id] = currentDepth
        else
            state[passive.Id] = currentDepth
        end
    end
end


--[[
    CanCastAbility(player, abilityId) -> (boolean, string?)
    Validate aspect, depth, state, mana, and cooldown.
]]
function AspectService.CanCastAbility(player: Player, abilityId: string)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.AspectData then
        return false, "NoAspect"
    end

    local ability = _getAbility(abilityId)
    if not ability then
        return false, "UnknownAbility"
    end

    if ability.AspectId and ability.AspectId ~= "None" then
        if profile.AspectData.AspectId ~= ability.AspectId then
            return false, "WrongAspect"
        end
    end

    if ability.Branch and ability.MinDepth then
        local branchState = profile.AspectData.Branches and profile.AspectData.Branches[ability.Branch]
        if not branchState or branchState.Depth < ability.MinDepth then
            return false, "DepthTooLow"
        end
    end

    if not StateService:IsActionAllowed(player, "CastAbility") then
        return false, "BadState"
    end

    if profile.Mana.Current < ability.ManaCost then
        return false, "InsufficientMana"
    end

    profile.ActiveCooldowns = profile.ActiveCooldowns or {}
    local now = tick()
    if profile.ActiveCooldowns[abilityId] and profile.ActiveCooldowns[abilityId] > now then
        return false, "OnCooldown"
    end

    return true
end


--[[
    ExecuteAbility(player, abilityId, targetPosition) -> boolean
    Validates and executes ability; handles mana, state, cooldown, and damage.
]]
function AspectService.ExecuteAbility(player: Player, abilityId: string, targetPosition: Vector3?)
    local ok, reason = AspectService.CanCastAbility(player, abilityId)
    if not ok then
        return false, reason
    end

    local profile = DataService:GetProfile(player)
    local ability = _getAbility(abilityId)
    if not ability then
        return false, "UnknownAbility"
    end

    profile.Mana.Current -= ability.ManaCost

    local cdExpiry = tick() + ability.Cooldown
    profile.ActiveCooldowns[abilityId] = cdExpiry

    local char = player.Character
    if char then
        char:SetAttribute("CD_" .. abilityId, cdExpiry)
    end

    StateService:SetState(player, "Casting")
    ability.VFX_Function(player, targetPosition)

    -- ── Issue 1 / 2: server-side hitbox → CombatService damage pipeline ──────
    if ability.BaseDamage and ability.BaseDamage > 0 then
        if targetPosition then
            local hitRadius = ability.Range or ABILITY_HIT_RADIUS
            local isAoE = ability.IsAoE == true

            if isAoE then
                -- AoE path: collect all targets then batch-validate (Issue 2)
                -- Build a temporary hitbox to identify targets in the sphere.
                local aoeHitbox = HitboxService.CreateHitbox({
                    Owner    = player,
                    Shape    = "Sphere",
                    Position = targetPosition,
                    Size     = Vector3.new(hitRadius, hitRadius, hitRadius),
                    Damage   = ability.BaseDamage,
                    LifeTime = ABILITY_HITBOX_LIFETIME,
                })
                -- Collect targets via OnHit before expiry
                local aoeHits: {{TargetName: string, Damage: number, HitType: string?}} = {}
                local origOnHit = aoeHitbox.Config.OnHit
                aoeHitbox.Config.OnHit = function(target: any, _hd: any)
                    local targetName: string? = nil
                    if typeof(target) == "Instance" and target:IsA("Player") then
                        targetName = (target :: Player).Name
                    elseif type(target) == "string" then
                        targetName = target
                    end
                    if targetName then
                        table.insert(aoeHits, {
                            TargetName = targetName,
                            Damage     = ability.BaseDamage :: number,
                            HitType    = "Ability",
                        })
                    end
                    if origOnHit then origOnHit(target, _hd) end
                end
                HitboxService.TestHitbox(aoeHitbox)
                -- Validate all hits server-side, rate-limit bypassed (server-initiated)
                if #aoeHits > 0 then
                    task.spawn(function()
                        CombatService.ValidateAoEHit(player, aoeHits)
                    end)
                end
            else
                -- Single-target path: Sphere hitbox, hit first valid target (Issue 1)
                local hitHappened = false
                local singleHitbox = HitboxService.CreateHitbox({
                    Owner    = player,
                    Shape    = "Sphere",
                    Position = targetPosition,
                    Size     = Vector3.new(hitRadius, hitRadius, hitRadius),
                    Damage   = ability.BaseDamage,
                    LifeTime = ABILITY_HITBOX_LIFETIME,
                    OnHit    = function(target: any, _hd: any)
                        if hitHappened then return end  -- first-hit gate
                        hitHappened = true
                        local targetName: string? = nil
                        if typeof(target) == "Instance" and target:IsA("Player") then
                            targetName = (target :: Player).Name
                        elseif type(target) == "string" then
                            targetName = target
                        end
                        if not targetName then return end
                        CombatService.ValidateHit(player, {
                            TargetName             = targetName,
                            Damage                 = ability.BaseDamage :: number,
                            HitType                = "Ability",
                            BypassWeaponValidation = true,
                            BypassRateLimit        = true,
                        })
                    end,
                })
                HitboxService.TestHitbox(singleHitbox)
            end
        else
            warn(`[AspectService] {player.Name} cast {abilityId} with no targetPosition — hitbox skipped`)
        end
    end
    -- ─────────────────────────────────────────────────────────────────────────

    -- return to idle after cast time
    task.delay(ability.CastTime or 0, function()
        if Utils.IsValidPlayer(player) then
            StateService:SetState(player, "Idle")
        end
    end)

    return true
end

-- cooldown sync
function AspectService:GetCooldowns(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile then return {} end
    return profile.ActiveCooldowns or {}
end

-- mana regen heartbeat
local function _onHeartbeat(dt)
    for _, player in pairs(Players:GetPlayers()) do
        local profile = DataService:GetProfile(player)
        if profile then
            local mana = profile.Mana
            if mana.Current < mana.Max then
                -- simple regen delay check
                mana._regenTimer = (mana._regenTimer or 0) + dt
                if mana._regenTimer >= mana.RegenDelay then
                    mana.Current = math.min(mana.Max, mana.Current + mana.Regen * dt)
                end
            else
                mana._regenTimer = 0
            end
        end
    end
end

-- event listeners for network requests
local function _onInvestRequest(player, aspectId, branch, amount)
    local success, reason = AspectService.InvestInBranch(player, aspectId, branch, amount)
    NetworkService:SendToClient(player, "AspectInvestResult", {Success = success, Reason = reason})
end

-- Issue 3: packet validation + authoritative cooldown timestamp ─────────────
local function _onCastRequest(player: Player, packet: any)
    -- nil / type guards
    if type(packet) ~= "table" then
        warn(`[AspectService] {player.Name} sent non-table AbilityCastRequest`)
        NetworkService:SendToClient(player, "AbilityCastResult", {
            Success = false, Reason = "InvalidPacket"
        })
        return
    end
    if type(packet.AbilityId) ~= "string" or packet.AbilityId == "" then
        warn(`[AspectService] {player.Name} sent missing/empty AbilityId`)
        NetworkService:SendToClient(player, "AbilityCastResult", {
            Success = false, Reason = "InvalidAbilityId"
        })
        return
    end
    -- TargetPosition: optional but must be a Vector3 if provided
    local targetPosition: Vector3? = nil
    if packet.TargetPosition ~= nil then
        if typeof(packet.TargetPosition) ~= "Vector3" then
            warn(`[AspectService] {player.Name} sent non-Vector3 TargetPosition`)
            NetworkService:SendToClient(player, "AbilityCastResult", {
                Success = false, Reason = "InvalidTargetPosition", AbilityId = packet.AbilityId
            })
            return
        end
        -- Range sanity check: reject casts beyond MAX_CAST_RANGE studs
        local char = player.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            if root then
                local dist = (root.Position - packet.TargetPosition).Magnitude
                if dist > MAX_CAST_RANGE then
                    warn(`[AspectService] {player.Name} exceeded cast range ({dist} studs)`)
                    NetworkService:SendToClient(player, "AbilityCastResult", {
                        Success = false, Reason = "OutOfRange", AbilityId = packet.AbilityId
                    })
                    return
                end
            end
        end
        targetPosition = packet.TargetPosition
    end

    -- Route: general weapon/inventory abilities → AbilitySystem (no AspectData required)
    --        Expression (Depth-1) abilities     → AbilitySystem.HandleExpressionAbility (with targetPos)
    --        Aspect-specific abilities          → AspectService.ExecuteAbility
    local generalAbility = AbilityRegistry.Get(packet.AbilityId)
    if generalAbility then
        if generalAbility.Type == "Expression" then
            -- Expression abilities need the targetPosition for spatial effects (dash direction, etc.)
            _requireAbilitySystem().HandleExpressionAbility(player, packet.AbilityId, targetPosition)
        else
            _requireAbilitySystem().HandleUseAbilityById(player, packet.AbilityId)
        end
        NetworkService:SendToClient(player, "AbilityCastResult", {
            Success        = true,
            Reason         = nil,
            AbilityId      = packet.AbilityId,
            TargetPosition = targetPosition,
            CooldownExpiry = nil,
        })
        return
    end

    local success, reason = AspectService.ExecuteAbility(player, packet.AbilityId, targetPosition)

    -- Return authoritative server-side cooldown expiry so client doesn't recalculate
    local cooldownExpiry: number? = nil
    if success then
        local profile = DataService:GetProfile(player)
        if profile and profile.ActiveCooldowns then
            cooldownExpiry = profile.ActiveCooldowns[packet.AbilityId]
        end
    end

    NetworkService:SendToClient(player, "AbilityCastResult", {
        Success        = success,
        Reason         = reason,
        AbilityId      = packet.AbilityId,
        TargetPosition = targetPosition,
        CooldownExpiry = cooldownExpiry,  -- authoritative server tick() expiry timestamp
    })
end
-- ────────────────────────────────────────────────────────────────────────────

-- sync cooldowns on join
local function _onPlayerAdded(player)
    NetworkService:SendToClient(player, "AbilityDataSync", AspectService:GetCooldowns(player))
    AspectService.ApplyPassives(player)
end

--[[
    Init and Start
]]
function AspectService:Init()
    print("[AspectService] Initializing...")
    Players.PlayerAdded:Connect(_onPlayerAdded)
    Players.PlayerRemoving:Connect(function(player)
        -- cleanups if necessary
    end)
    print("[AspectService] Initialized successfully")
end

function AspectService:Start()
    print("[AspectService] Starting...")
    NetworkService:RegisterHandler("AspectInvestRequest", function(player, packet)
        -- packet is {AspectId, Branch, Amount}
        _onInvestRequest(player, packet.AspectId, packet.Branch, packet.Amount)
    end)
    NetworkService:RegisterHandler("AbilityCastRequest", function(player, packet)
        -- Pass the whole packet table; _onCastRequest performs its own nil/type guards (Issue 3)
        _onCastRequest(player, packet)
    end)
    NetworkService:RegisterHandler("SwitchAspectRequest", function(player, packet)
        if type(packet) ~= "table" then
            NetworkService:SendToClient(player, "SwitchAspectResult", {
                Success = false, Reason = "InvalidPacket"
            })
            return
        end
        -- packet.AspectId may be a string or nil (explicit nil = clear)
        local requestedId = packet.AspectId  -- nil is valid (clear aspect)
        if requestedId ~= nil and type(requestedId) ~= "string" then
            NetworkService:SendToClient(player, "SwitchAspectResult", {
                Success = false, Reason = "InvalidAspectId"
            })
            return
        end
        local success, reason = AspectService.SwitchAspect(player, requestedId)
        if not success then
            NetworkService:SendToClient(player, "SwitchAspectResult", {
                Success = false, Reason = reason, AspectId = requestedId
            })
        end
        -- success path already fires SwitchAspectResult inside SwitchAspect()
    end)

    RunService.Heartbeat:Connect(_onHeartbeat)
    print("[AspectService] Started successfully")
end

return AspectService
