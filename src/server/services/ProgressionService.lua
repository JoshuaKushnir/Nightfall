--!strict
--[[
    Class: ProgressionService
    Description: Server authority for all player progression — Resonance accumulation,
                 Ring-based soft caps with diminishing returns, Resonance Shard loss on
                 death, and Discipline selection lock-in.

    Issue #138: ProgressionService — Resonance grants, Ring soft caps, Shard loss on death
    Issue #139: Discipline selection flow
    Epic #51: Phase 4 — World & Narrative

    Public API:
        ProgressionService.GrantResonance(player, amount, source)
            → Awards Resonance from a validated source; applies soft cap + diminishing returns.
        ProgressionService.OnPlayerDied(player)
            → Deducts 15% of ResonanceShards; fires update to client.
        ProgressionService.SetPlayerRing(player, ring)
            → Updates CurrentRing; used by world systems when the player enters a new zone.
        ProgressionService.SelectDiscipline(player, disciplineId)
            → Validates and locks in the player's Discipline choice (one-time).
        ProgressionService.SyncToClient(player)
            → Sends full ProgressionSync packet to client (called on join).

    Dependencies: DataService, NetworkService, DisciplineConfig
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local NetworkService = require(script.Parent.NetworkService)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)
local ProgressionTypes = require(ReplicatedStorage.Shared.types.ProgressionTypes)

local RING_CONFIGS        = ProgressionTypes.RING_CONFIGS
local RESONANCE_GRANTS    = ProgressionTypes.RESONANCE_GRANTS
local SHARD_LOSS_FRACTION = ProgressionTypes.SHARD_LOSS_FRACTION
local VALID_DISCIPLINES   = ProgressionTypes.VALID_DISCIPLINES

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
    })
end

--[[
    _applyDisciplineStats(player, profile, disciplineId)
    Adjusts the player's base Posture and Health pools according to
    the numeric values in DisciplineConfig. The sourced stats become the
    player's new values; downstream services read DisciplineConfig by Id.
]]
local function _applyDisciplineStats(player: Player, profile: any, disciplineId: string)
    local cfg = DisciplineConfig[disciplineId]
    if not cfg then
        warn(("[ProgressionService] No DisciplineConfig entry for '%s'"):format(disciplineId))
        return
    end

    -- Apply posture pool
    if cfg.postureMax then
        profile.Posture.Max     = cfg.postureMax
        profile.Posture.Current = cfg.postureMax
    end

    -- Some disciplines have breath pools that map to Mana for now (placeholder)
    -- SPEC-GAP: Breath is a separate resource — once MovementController is updated
    --           to track Breath separately, remove this.

    -- Apply character Humanoid health to match the new pool (if character exists)
    local char = player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.MaxHealth = profile.Health.Max
            humanoid.Health    = math.min(humanoid.Health, profile.Health.Max)
        end
    end

    print(("[ProgressionService] Applied Discipline stats for '%s' to %s"):format(disciplineId, player.Name))
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

    -- TotalResonance: always grows (permanent accumulation)
    profile.TotalResonance = (profile.TotalResonance or 0) + amount

    -- Shards: subject to soft cap + diminishing returns
    local shardGrant, isCapped = _computeShardGrant(profile.TotalResonance - amount, ring, amount)
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
    SelectDiscipline(player, disciplineId) -> (boolean, string?)
    Locks in the player's Discipline choice.
    Only allowed once — returns false if already chosen.
    Applies stat modifiers from DisciplineConfig.

    @param player       The choosing player
    @param disciplineId One of "Wayward" | "Ironclad" | "Silhouette" | "Resonant"
    @returns (success, errorReason?)
]]
function ProgressionService.SelectDiscipline(player: Player, disciplineId: string): (boolean, string?)
    -- Validate the id
    if not VALID_DISCIPLINES[disciplineId] then
        warn(("[ProgressionService] %s sent invalid DisciplineId: '%s'"):format(player.Name, disciplineId))
        return false, "InvalidDiscipline"
    end

    local profile = DataService:GetProfile(player)
    if not profile then
        return false, "NoProfile"
    end

    -- One-time selection enforcement
    if profile.HasChosenDiscipline then
        warn(("[ProgressionService] %s attempted to re-select Discipline (already: %s)")
            :format(player.Name, profile.DisciplineId))
        return false, "AlreadyChosen"
    end

    -- Lock in
    profile.DisciplineId        = disciplineId
    profile.HasChosenDiscipline = true

    -- Apply stat changes from DisciplineConfig
    _applyDisciplineStats(player, profile, disciplineId)

    print(("[ProgressionService] ✓ %s selected Discipline: %s"):format(player.Name, disciplineId))

    -- Confirm to client
    NetworkService:SendToClient(player, "DisciplineConfirmed", {
        DisciplineId = disciplineId,
    })

    return true, nil
end

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

    NetworkService:SendToClient(player, "ProgressionSync", {
        TotalResonance      = profile.TotalResonance or 0,
        ResonanceShards     = profile.ResonanceShards or 0,
        CurrentRing         = ring,
        SoftCap             = softCap,
        HasChosenDiscipline = profile.HasChosenDiscipline or false,
        DisciplineId        = profile.DisciplineId or "Wayward",
        OmenMarks           = profile.OmenMarks or 0,
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

    -- Send full state to client
    ProgressionService.SyncToClient(player)

    -- If discipline not yet chosen, prompt the selection UI
    if not profile.HasChosenDiscipline then
        task.wait(0.5)  -- slight delay so client UI is ready
        if player.Parent then
            NetworkService:SendToClient(player, "DisciplineSelectRequired", {})
            print(("[ProgressionService] Sent DisciplineSelectRequired to %s"):format(player.Name))
        end
    end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function ProgressionService:Init()
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

    -- Discipline selection handler
    NetworkService:RegisterHandler("DisciplineSelected", function(player: Player, packet: any)
        if type(packet) ~= "table" or type(packet.DisciplineId) ~= "string" then
            warn(("[ProgressionService] Bad DisciplineSelected packet from %s"):format(player.Name))
            return
        end
        ProgressionService.SelectDiscipline(player, packet.DisciplineId)
    end)

    print("[ProgressionService] Started successfully")
end

return ProgressionService
