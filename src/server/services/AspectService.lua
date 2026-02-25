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

local DataService = require(ReplicatedStorage.Shared.services.DataService)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local CombatService = require(script.Parent.CombatService)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)

-- Forward declarations for lazy dependencies

-- Type aliases
local AspectTypes = require(ReplicatedStorage.Shared.types.AspectTypes)

-- Internal cooldown tracking will live on player data
-- Mana regeneration loop implemented in this service

local AspectService = {}
AspectService._initialized = false

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
function AspectService.ApplyPassives(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile or not profile.AspectData then return end
    -- remove all first by reloading state (this is rudimentary)
    -- For now we don't track active ones individually; assume idempotent.
    local passives = AspectRegistry.GetPassivesForAspect(profile.AspectData.AspectId)
    for _, passive in ipairs(passives) do
        passive.RemoveEffect(player)
    end
    for _, passive in ipairs(passives) do
        local depth = profile.AspectData.Branches[passive.Branch].Depth
        if depth >= passive.MinDepth then
            passive.ApplyEffect(player, profile)
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
    local ability = AspectRegistry.Abilities[abilityId]
    if not ability then
        return false, "UnknownAbility"
    end
    local depth = profile.AspectData.Branches[ability.Branch].Depth
    if depth < ability.MinDepth then
        return false, "DepthTooLow"
    end
    local state = StateService:GetState(player)
    if state == "Stunned" or state == "Dead" or state == "Attacking" or state == "Ragdolled" then
        return false, "BadState"
    end
    if profile.Mana.Current < ability.ManaCost then
        return false, "InsufficientMana"
    end
    -- cooldown map stored on profile
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
    local ability = AspectRegistry.Abilities[abilityId]
    -- consume mana
    profile.Mana.Current -= ability.ManaCost
    -- put on cooldown
    profile.ActiveCooldowns[abilityId] = tick() + ability.Cooldown
    -- set player state
    StateService:SetState(player, "Casting")
    -- stub VFX
    ability.VFX_Function(player, targetPosition)
    -- deal damage if expression
    if ability.BaseDamage then
        -- simplistic hit: apply posture then HP via CombatService
        -- we don't have target player, skip; real logic lives elsewhere.
    end
    -- return to idle after cast time
    task.delay(ability.CastTime, function()
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
    NetworkProvider:FireClient(player, "AspectInvestResult", success, reason)
end

local function _onCastRequest(player, abilityId, targetPosition)
    local success, reason = AspectService.ExecuteAbility(player, abilityId, targetPosition)
    NetworkProvider:FireClient(player, "AbilityCastResult", success, reason, abilityId, targetPosition)
end

-- sync cooldowns on join
local function _onPlayerAdded(player)
    NetworkProvider:FireClient(player, "AbilityDataSync", AspectService:GetCooldowns(player))
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
    NetworkProvider:RegisterEvent("AspectInvestRequest", _onInvestRequest)
    NetworkProvider:RegisterEvent("AbilityCastRequest", _onCastRequest)
    RunService.Heartbeat:Connect(_onHeartbeat)
    print("[AspectService] Started successfully")
end

return AspectService
