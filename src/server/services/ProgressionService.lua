--!strict
--[[
    Class: ProgressionService
    Description: Server authority for all player progression — Resonance accumulation,
                 Ring-based soft caps with diminishing returns, Resonance Shard loss on
                 death, and stat-based progression.

    Issue #138: ProgressionService — Resonance grants, Ring soft caps, Shard loss on death
    Issue #140: Stat-based progression — replace Discipline lock-in
    Epic #51: Phase 4 — World & Narrative

    Public API:
        ProgressionService.GrantResonance(player, amount, source)
            → Awards Resonance; applies soft cap + diminishing returns; grants stat points at milestones.
        ProgressionService.OnPlayerDied(player)
            → Deducts 15% of ResonanceShards; fires update to client.
        ProgressionService.SetPlayerRing(player, ring)
            → Updates CurrentRing; used by world systems when the player enters a new zone.
        ProgressionService.AllocateStat(player, statName, amount)
            → Spends unspent StatPoints into a stat, applies derived values, recomputes DisciplineId.
        ProgressionService.SyncToClient(player)
            → Sends full ProgressionSync packet to client (called on join).

    Dependencies: DataService, NetworkService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService: any = nil
local NetworkService: any = nil
local ProgressionTypes = require(ReplicatedStorage.Shared.types.ProgressionTypes)

local RING_CONFIGS           = ProgressionTypes.RING_CONFIGS
local RESONANCE_GRANTS       = ProgressionTypes.RESONANCE_GRANTS
local SHARD_LOSS_FRACTION    = ProgressionTypes.SHARD_LOSS_FRACTION
local VALID_STAT_NAMES       = ProgressionTypes.VALID_STAT_NAMES
local STAT_POINT_MILESTONE   = ProgressionTypes.STAT_POINT_MILESTONE
local ENABLE_STAT_POINT_MILESTONES = ProgressionTypes.ENABLE_STAT_POINT_MILESTONES
local STAT_MAX_PER_STAT      = ProgressionTypes.STAT_MAX_PER_STAT
local STAT_PER_POINT         = ProgressionTypes.STAT_PER_POINT
local DISCIPLINE_STAT_MAP    = ProgressionTypes.DISCIPLINE_STAT_MAP

local ProgressionService = {}
ProgressionService._initialized = false

-- Expose grant table so CombatService can read amounts without a second require
ProgressionService.RESONANCE_GRANTS = RESONANCE_GRANTS

-- ─── Private Helpers ──────────────────────────────────────────────────────────

--[[
    _getRingConfig(ring) -> RingConfig
    Returns the config for the given ring index, defaulting to Ring 1 if out of range.
]]
local function _getRingConfig(ring: number): typeof(RING_CONFIGS[1])
    return RING_CONFIGS[ring] or RING_CONFIGS[1]
end

--[[
    _computeShardGrant(totalResonance, ring, rawAmount) -> (shardAmount, isSoftCapped)
    Applies soft cap and diminishing returns to a raw Resonance grant.
    Returns the effective Shard amount the player actually receives plus whether
    they're currently at the hard cap.
]]
local function _computeShardGrant(totalResonance: number, ring: number, rawAmount: number): (number, boolean)
    local cfg = _getRingConfig(ring)

    if cfg.SoftCap == math.huge then
        -- No cap (Ring 0 or Ring 5)
        return rawAmount, false
    end

    if totalResonance >= cfg.SoftCap then
        -- Already at hard cap; Shards are fully blocked
        return 0, true
    end

    local diminishAt = cfg.SoftCap * cfg.DiminishThreshold

    if totalResonance < diminishAt then
        -- Below diminishing threshold: full grant
        return rawAmount, false
    end

    -- In diminishing range [diminishAt, SoftCap)
    -- Apply the DiminishMultiplier
    local effective = math.max(1, math.floor(rawAmount * cfg.DiminishMultiplier))
    return effective, false
end

--[[
    _syncToClient(player, profile, shardDelta, source)
    Fires ResonanceUpdate to the client with the current state.
    shardDelta is the signed change this update caused (positive = gain, negative = loss).
    source is nil for death-loss events.
]]
local function _syncToClient(player: Player, profile: any, shardDelta: number, source: string?)
    local ring = profile.CurrentRing or 1
    local cfg = _getRingConfig(ring)
    local softCap = cfg.SoftCap == math.huge and -1 or cfg.SoftCap  -- -1 signals "no cap" to client

    NetworkService:SendToClient(player, "ResonanceUpdate", {
        TotalResonance = profile.TotalResonance,
        ResonanceShards = profile.ResonanceShards,
        CurrentRing     = ring,
        SoftCap         = softCap,
        ShardDelta      = shardDelta,
        IsSoftCapped    = cfg.SoftCap ~= math.huge and profile.TotalResonance >= cfg.SoftCap,
        Source          = source,
        StatPoints      = profile.StatPoints or 0,
    })
end

--[[
    _computeDisciplineLabel(profile) -> string
    Derives a soft Discipline label from the player's stat allocation.
    Checks for clear dominance; ties default to Wayward.
]]
local function _computeDisciplineLabel(profile: any): string
    local stats = profile.Stats or {}

    -- Weighted score per label
    local scores: {[string]: number} = {
        Ironclad   = (stats.Fortitude or 0),
        Silhouette = (stats.Agility or 0),
        Resonant   = (stats.Intelligence or 0) + (stats.Willpower or 0) * 0.5,
        Wayward    = (stats.Strength or 0) + (stats.Charisma or 0) * 0.3,
    }

    local best: string = "Wayward"
    local bestScore = 0
    for label, score in pairs(scores) do
        if score > bestScore then
            bestScore = score
            best = label
        end
    end
    return best
end

--[[
    _applyStats(player, profile)
    Recomputes Player data component values (Health.Max, Posture.Max, Mana.Max, Mana.Regen)
    from the current stat allocation, then updates the Humanoid if character is loaded.
    Base values are defined in DataService DEFAULT_PLAYER_DATA and are the 0-point baseline.
]]
local function _applyStats(player: Player, profile: any)
    local stats = profile.Stats or {}

    -- Base values (before any stat points)
    local healthMax  = 100
    local postureMax = 100
    local manaMax    = 100
    local manaRegen  = 2.0
    local breakBase  = 45
    local postureRecovery: number = 5.0

    for statName, points in pairs(stats) do
        local scale = STAT_PER_POINT[statName]
        if scale and points > 0 then
            healthMax       = healthMax       + (scale.HealthMax       or 0) * points
            postureMax      = postureMax      + (scale.PostureMax      or 0) * points
            manaMax         = manaMax         + (scale.ManaMax         or 0) * points
            manaRegen       = manaRegen       + (scale.ManaRegen       or 0) * points
            breakBase       = breakBase       + (scale.BreakBase       or 0) * points
            postureRecovery = postureRecovery + (scale.PostureRecovery  or 0) * points
        end
    end

    -- Apply to profile components
    profile.Health.Max     = math.floor(healthMax)
    profile.Health.Current = math.min(profile.Health.Current or healthMax, profile.Health.Max)
    profile.Posture.Max    = math.floor(postureMax)
    profile.Mana.Max       = math.floor(manaMax)
    profile.Mana.Regen     = manaRegen

    -- Update Humanoid if character is loaded
    local char = player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.MaxHealth = profile.Health.Max
            humanoid.Health    = math.min(humanoid.Health, profile.Health.Max)

            -- Agility → walk speed: +0.5 studs/s per point, base 16
            -- Store as attribute so MovementController can read the authoritative base
            local baseSpeed = 16 + (stats.Agility or 0) * 0.5
            humanoid:SetAttribute("BaseWalkSpeed", baseSpeed)
            -- Only set WalkSpeed when the player isn't in a movement state that
            -- overrides it (e.g. sprinting); MovementController checks the attribute.
            if humanoid.WalkSpeed > 0 then
                humanoid.WalkSpeed = baseSpeed
            end
        end
    end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
    GrantResonance(player, amount, source)
    Awards Resonance from an authoritative server source.

    - TotalResonance always increases by the raw amount (permanent).
    - ResonanceShards increase by the effective amount after soft cap + diminishing returns.
    - Fires ResonanceUpdate to the client.

    @param player  The receiving player
    @param amount  Raw Resonance amount before cap calculations
    @param source  ResonanceSource string for logging and client display
]]
function ProgressionService.GrantResonance(player: Player, amount: number, source: string)
    if amount <= 0 then return end

    local profile = DataService:GetProfile(player)
    if not profile then return end

    local ring = profile.CurrentRing or 1
    local prevTotal = profile.TotalResonance or 0

    -- TotalResonance: always grows (permanent accumulation)
    profile.TotalResonance = prevTotal + amount

    -- Shards: subject to soft cap + diminishing returns
    local shardGrant, isCapped = _computeShardGrant(prevTotal, ring, amount)
    profile.ResonanceShards = (profile.ResonanceShards or 0) + shardGrant

    if isCapped then
        print(("[ProgressionService] %s at Ring %d soft cap — Shards blocked (grant source: %s)")
            :format(player.Name, ring, source))
    elseif shardGrant < amount then
        print(("[ProgressionService] %s diminishing returns: %d → %d Shards (source: %s)")
            :format(player.Name, amount, shardGrant, source))
    else
        print(("[ProgressionService] %s +%d Resonance / +%d Shards (source: %s)")
            :format(player.Name, amount, shardGrant, source))
    end

    -- ─── Stat point milestones ───────────────────────────────────────────────────────
    -- Award 1 StatPoint per STAT_POINT_MILESTONE of TotalResonance crossed
    -- Only award if ENABLE_STAT_POINT_MILESTONES is true (allows transition to training tools)
    if ProgressionTypes.ENABLE_STAT_POINT_MILESTONES then
        local prevMilestone = math.floor(prevTotal / STAT_POINT_MILESTONE)
        local newMilestone  = math.floor(profile.TotalResonance / STAT_POINT_MILESTONE)
        local newPoints     = newMilestone - prevMilestone
        if newPoints > 0 then
            profile.StatPoints = (profile.StatPoints or 0) + newPoints
            print(("[ProgressionService] %s earned %d stat point(s) (milestone %d→%d, total unspent: %d)")
                :format(player.Name, newPoints, prevMilestone, newMilestone, profile.StatPoints))
        end
    end

    _syncToClient(player, profile, shardGrant, source)
end

--[[
    OnPlayerDied(player)
    Deducts SHARD_LOSS_FRACTION of current ResonanceShards and fires
    a ResonanceUpdate with the negative delta.

    Called from the character Died connection established in Start().
    TotalResonance is NEVER reduced — only Shards.
]]
function ProgressionService.OnPlayerDied(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile then return end

    local currentShards = profile.ResonanceShards or 0
    if currentShards <= 0 then return end

    local loss = math.floor(currentShards * SHARD_LOSS_FRACTION)
    if loss < 1 then loss = 1 end  -- always lose at least 1 if you have any Shards

    profile.ResonanceShards = math.max(0, currentShards - loss)

    print(("[ProgressionService] ☠ %s died — lost %d Shards (%.0f%%) [%d → %d]")
        :format(player.Name, loss, SHARD_LOSS_FRACTION * 100, currentShards, profile.ResonanceShards))

    _syncToClient(player, profile, -loss, nil)

    -- #144: fire dedicated ShardLost event so DeathController can show popup
    NetworkService:SendToClient(player, "ShardLost", {
        Loss     = loss,
        NewTotal = profile.ResonanceShards,
        Fraction = SHARD_LOSS_FRACTION,
    })
end

--[[
    SetPlayerRing(player, ring)
    Called by world zone systems when a player physically enters a new Ring.
    Removes the previous ring's soft cap so gains from the new Ring flow normally.

    @param ring  RingId (0-5). Values outside this range are clamped.
]]
function ProgressionService.SetPlayerRing(player: Player, ring: number)
    ring = math.clamp(ring, 0, 5)

    local profile = DataService:GetProfile(player)
    if not profile then return end

    local previousRing = profile.CurrentRing or 1
    if previousRing == ring then return end

    profile.CurrentRing = ring

    print(("[ProgressionService] %s moved Ring %d → Ring %d")
        :format(player.Name, previousRing, ring))

    -- Sync so client HUD reflects the new cap immediately
    _syncToClient(player, profile, 0, nil)
end

--[[
    AllocateStat(player, statName, amount) -> (boolean, string?)
    Spends `amount` unspent StatPoints into `statName`.
    Applies derived combat values and recomputes the DisciplineId soft label.
    Fires StatAllocated to client on success.

    @param statName  One of the StatName values (Strength, Fortitude, Agility, …)
    @param amount    How many points to invest (usually 1)
    @returns (success, errorReason?)
]]
function ProgressionService.AllocateStat(player: Player, statName: string, amount: number): (boolean, string?)
    -- Validate stat name
    if not VALID_STAT_NAMES[statName] then
        warn(("[ProgressionService] %s sent invalid stat name: '%s'"):format(player.Name, statName))
        return false, "InvalidStat"
    end

    amount = math.floor(amount or 1)
    if amount < 1 then return false, "InvalidAmount" end

    local profile = DataService:GetProfile(player)
    if not profile then return false, "NoProfile" end

    -- Ensure Stats subtable exists (reconcile for old profiles)
    if not profile.Stats then
        profile.Stats = { Strength=0, Fortitude=0, Agility=0, Intelligence=0, Willpower=0, Charisma=0 }
    end

    -- Validate unspent points
    local unspent = profile.StatPoints or 0
    if unspent < amount then
        warn(("[ProgressionService] %s tried to spend %d points in %s with only %d unspent")
            :format(player.Name, amount, statName, unspent))
        return false, "NotEnoughPoints"
    end

    -- Validate per-stat cap
    local current = profile.Stats[statName] or 0
    if current + amount > STAT_MAX_PER_STAT then
        local allowable = STAT_MAX_PER_STAT - current
        warn(("[ProgressionService] %s would exceed %s cap (at %d, max %d, requested %d)")
            :format(player.Name, statName, current, STAT_MAX_PER_STAT, amount))
        if allowable <= 0 then return false, "StatCapped" end
        amount = allowable  -- clamp to what's allowed
    end

    -- Apply
    profile.StatPoints          = unspent - amount
    profile.Stats[statName]     = current + amount

    -- Recompute derived combat values
    _applyStats(player, profile)

    -- Recompute Discipline soft label
    local newLabel = _computeDisciplineLabel(profile)
    if profile.DisciplineId ~= newLabel then
        print(("[ProgressionService] %s Discipline label updated: %s → %s")
            :format(player.Name, profile.DisciplineId or "?", newLabel))
    end
    profile.DisciplineId = newLabel

    print(("[ProgressionService] ✔ %s +%d %s (total: %d / remaining: %d unspent)")
        :format(player.Name, amount, statName, profile.Stats[statName], profile.StatPoints))

    -- Inform client
    NetworkService:SendToClient(player, "StatAllocated", {
        StatName     = statName,
        NewAmount    = profile.Stats[statName],
        StatPoints   = profile.StatPoints,
        DisciplineId = profile.DisciplineId,
        HealthMax    = profile.Health.Max,
        PostureMax   = profile.Posture.Max,
        ManaMax      = profile.Mana.Max,
        ManaRegen    = profile.Mana.Regen,
    })

    return true, nil
end

--[[
    SelectDiscipline has been removed (Issue #140).
    Discipline is now a computed soft label — use AllocateStat instead.
]]

--[[
    SyncToClient(player)
    Fires the full ProgressionSync packet. Called on join after profile loads.
]]
function ProgressionService.SyncToClient(player: Player)
    local profile = DataService:GetProfile(player)
    if not profile then return end

    local ring = profile.CurrentRing or 1
    local cfg  = _getRingConfig(ring)
    local softCap = cfg.SoftCap == math.huge and -1 or cfg.SoftCap

    -- Ensure Stats subtable exists on old profiles
    local stats = profile.Stats or { Strength=0, Fortitude=0, Agility=0, Intelligence=0, Willpower=0, Charisma=0 }

    -- Ensure discipline label is current
    local label = _computeDisciplineLabel(profile)
    if profile.DisciplineId ~= label then
        profile.DisciplineId = label
    end

    NetworkService:SendToClient(player, "ProgressionSync", {
        TotalResonance  = profile.TotalResonance or 0,
        ResonanceShards = profile.ResonanceShards or 0,
        CurrentRing     = ring,
        SoftCap         = softCap,
        DisciplineId    = profile.DisciplineId or "Wayward",
        OmenMarks       = profile.OmenMarks or 0,
        StatPoints      = profile.StatPoints or 0,
        Stats           = stats,
        CodexEntries    = profile.CodexEntries or {},
        ActiveEmberPointId = profile.ActiveEmberPointId,
    })
end

-- ─── Internal Event Handlers ──────────────────────────────────────────────────

local function _onCharacterAdded(player: Player, character: Model)
    local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
    if not humanoid then return end

    humanoid.Died:Connect(function()
        ProgressionService.OnPlayerDied(player)
    end)
end

local function _onPlayerAdded(player: Player)
    -- Connect character for Died events (handles respawn too)
    player.CharacterAdded:Connect(function(char)
        _onCharacterAdded(player, char)
    end)
    if player.Character then
        _onCharacterAdded(player, player.Character)
    end

    -- Wait for DataService profile to load before syncing
    local waited = 0
    local profile = DataService:GetProfile(player)
    while not profile and player.Parent do
        task.wait(0.1)
        waited += 0.1
        profile = DataService:GetProfile(player)
        if waited >= 5 then
            warn(("[ProgressionService] Timed out waiting for profile: %s"):format(player.Name))
            return
        end
    end
    if not profile then return end

    -- Ensure Stats subtable exists on profiles created before Issue #140
    if not profile.Stats then
        profile.Stats = { Strength=0, Fortitude=0, Agility=0, Intelligence=0, Willpower=0, Charisma=0 }
    end

    -- Send full state to client
    ProgressionService.SyncToClient(player)
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function ProgressionService:Init(dependencies)

    if dependencies and dependencies.DataService then
        DataService = dependencies.DataService
    else
        DataService = require(script.Parent.DataService)
    end

    if dependencies and dependencies.NetworkService then
        NetworkService = dependencies.NetworkService
    else
        NetworkService = require(script.Parent.NetworkService)
    end
    print("[ProgressionService] Initializing...")
    self._initialized = true
    print("[ProgressionService] Initialized successfully")
end

function ProgressionService:Start()
    print("[ProgressionService] Starting...")

    -- Hook existing players (shouldn't happen on a fresh server, defensive)
    for _, player in Players:GetPlayers() do
        task.spawn(_onPlayerAdded, player)
    end

    Players.PlayerAdded:Connect(_onPlayerAdded)

    -- Stat allocation handler
    NetworkService:RegisterHandler("StatAllocate", function(player: Player, packet: any)
        if type(packet) ~= "table"
            or type(packet.StatName) ~= "string"
            or type(packet.Amount) ~= "number" then
            warn(("[ProgressionService] Bad StatAllocate packet from %s"):format(player.Name))
            return
        end
        ProgressionService.AllocateStat(player, packet.StatName, packet.Amount)
    end)

    -- Ember Point Placement
    NetworkService:RegisterHandler("EmberPointPlaceRequest", function(player: Player, packet: any)
        -- Validate ring rules (free in ring 1, otherwise assume ok for MVP)
        local profile = DataService:GetProfile(player)
        if not profile then return end
        
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        
        local pointId = game:GetService("HttpService"):GenerateGUID(false)
        local pos = root.Position
        
        if not profile.EmberPoints then profile.EmberPoints = {} end
        profile.EmberPoints[pointId] = {
            Id = pointId,
            Position = {X=pos.X, Y=pos.Y, Z=pos.Z},
            Ring = profile.CurrentRing or 1,
            SetAt = os.time(),
            UsedCount = 0
        }
        profile.ActiveEmberPointId = pointId
        
        NetworkService:SendToClient(player, "EmberPointDeployResult", {
            Success = true,
            EmberPointId = pointId
        })
        NetworkService:SendToClient(player, "EmberPointSync", {
            ActiveEmberPointId = pointId
        })
        print(("[ProgressionService] %s placed new Ember Point in Ring %d"):format(player.Name, profile.CurrentRing or 1))
    end)

    print("[ProgressionService] Started successfully")
end

return ProgressionService
