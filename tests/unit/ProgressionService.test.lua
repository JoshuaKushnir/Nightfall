--!strict
--[[
    ProgressionService Unit Tests
    Issue #138: ProgressionService — Resonance grants, Ring soft caps, Shard loss on death
    Issue #140: Stat-based progression — replace Discipline lock-in
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionTypes = require(ReplicatedStorage.Shared.types.ProgressionTypes)
local RING_CONFIGS        = ProgressionTypes.RING_CONFIGS
local SHARD_LOSS_FRACTION = ProgressionTypes.SHARD_LOSS_FRACTION
local VALID_STAT_NAMES    = ProgressionTypes.VALID_STAT_NAMES
local STAT_POINT_MILESTONE = ProgressionTypes.STAT_POINT_MILESTONE
local STAT_MAX_PER_STAT   = ProgressionTypes.STAT_MAX_PER_STAT

-- ── Stubs ────────────────────────────────────────────────────────────────────

-- Stub DataService so tests don't need a real session
local DataService = require(ReplicatedStorage.Server.services.DataService)
local _fakeProfiles: {[any]: any} = {}
DataService._profiles = _fakeProfiles

-- Stub NetworkService so no real remotes are touched
local NetworkService = require(ReplicatedStorage.Server.services.NetworkService)
NetworkService.SendToClient = function(_self, _player, _event, _packet) end
NetworkService.RegisterHandler = function(_self, _event, _fn) end

local ProgressionService = require(ReplicatedStorage.Server.services.ProgressionService)

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function makePlayer(overrides: {[string]: any}?): any
    local profile = {
        TotalResonance  = 0,
        ResonanceShards = 0,
        CurrentRing     = 1,
        DisciplineId    = "Wayward",
        StatPoints      = 0,
        OmenMarks       = 0,
        Stats = { Strength=0, Fortitude=0, Agility=0, Intelligence=0, Willpower=0, Charisma=0 },
        Posture = { Max = 100, Current = 100 },
        Health  = { Max = 100, Current = 100 },
        Mana    = { Max = 100, Current = 100, Regen = 2.0 },
    }
    if overrides then
        for k, v in overrides do
            profile[k] = v
        end
    end
    local fakePlayer: any = { UserId = math.random(1, 99999), Character = nil }
    DataService._profiles[fakePlayer] = {
        IsActive = function() return true end,
        Data = profile,
    }
    return fakePlayer
end

-- ── Tests ────────────────────────────────────────────────────────────────────

return {
    name = "ProgressionService Unit Tests",
    tests = {

        -- ─── GrantResonance ───────────────────────────────────────────────────

        {
            name = "GrantResonance: TotalResonance always increases by raw amount",
            fn = function()
                local p = makePlayer()
                local profile = DataService:GetProfile(p)
                ProgressionService.GrantResonance(p, 100, "Debug")
                assert(profile.TotalResonance == 100,
                    "TotalResonance should be 100, got " .. tostring(profile.TotalResonance))
            end,
        },

        {
            name = "GrantResonance: Shards equal raw amount when well below diminish threshold",
            fn = function()
                local p = makePlayer()
                local profile = DataService:GetProfile(p)
                -- Ring 1 cap = 2000, diminish at 75% = 1500. Start far below.
                ProgressionService.GrantResonance(p, 200, "Debug")
                assert(profile.ResonanceShards == 200,
                    "Shards should be 200 (no diminishing yet), got " .. tostring(profile.ResonanceShards))
            end,
        },

        {
            name = "GrantResonance: Diminishing returns applied above 75% cap for Ring 1",
            fn = function()
                -- Start TotalResonance at 1600 (above Ring 1's 75% threshold of 1500)
                local p = makePlayer({TotalResonance = 1600, ResonanceShards = 1600})
                local profile = DataService:GetProfile(p)
                local before = profile.ResonanceShards
                ProgressionService.GrantResonance(p, 100, "Debug")
                local shardGain = profile.ResonanceShards - before
                -- DiminishMultiplier = 0.10, so shards gained should be 10 (floor of 100 * 0.10)
                assert(shardGain == 10,
                    ("Expected 10 shards (diminished), got %d"):format(shardGain))
            end,
        },

        {
            name = "GrantResonance: Shards blocked entirely at soft cap (HardBlock = true)",
            fn = function()
                -- TotalResonance already at Ring 1 cap (2000)
                local p = makePlayer({TotalResonance = 2000, ResonanceShards = 500})
                local profile = DataService:GetProfile(p)
                local before = profile.ResonanceShards
                ProgressionService.GrantResonance(p, 50, "Debug")
                -- TotalResonance grew to 2050 (always grows)
                assert(profile.TotalResonance == 2050,
                    "TotalResonance should still grow, got " .. tostring(profile.TotalResonance))
                -- But Shards should be unchanged
                assert(profile.ResonanceShards == before,
                    ("Shards should be blocked at cap, expected %d got %d"):format(before, profile.ResonanceShards))
            end,
        },

        {
            name = "GrantResonance: Ring 5 has no cap (math.huge)",
            fn = function()
                local p = makePlayer({CurrentRing = 5, TotalResonance = 500000, ResonanceShards = 0})
                local profile = DataService:GetProfile(p)
                ProgressionService.GrantResonance(p, 100, "Debug")
                assert(profile.ResonanceShards == 100,
                    "Ring 5 has no cap — full grant expected, got " .. tostring(profile.ResonanceShards))
            end,
        },

        -- ─── OnPlayerDied ──────────────────────────────────────────────────────

        {
            name = "OnPlayerDied: deducts 15% of current ResonanceShards",
            fn = function()
                local p = makePlayer({ResonanceShards = 1000})
                local profile = DataService:GetProfile(p)
                ProgressionService.OnPlayerDied(p)
                local expected = 1000 - math.floor(1000 * SHARD_LOSS_FRACTION)  -- 850
                assert(profile.ResonanceShards == expected,
                    ("Expected %d Shards after death, got %d"):format(expected, profile.ResonanceShards))
            end,
        },

        {
            name = "OnPlayerDied: TotalResonance is never reduced",
            fn = function()
                local p = makePlayer({TotalResonance = 500, ResonanceShards = 200})
                local profile = DataService:GetProfile(p)
                ProgressionService.OnPlayerDied(p)
                assert(profile.TotalResonance == 500,
                    "TotalResonance must never decrease on death")
            end,
        },

        {
            name = "OnPlayerDied: deducts at least 1 Shard when balance is very low",
            fn = function()
                local p = makePlayer({ResonanceShards = 1})
                local profile = DataService:GetProfile(p)
                ProgressionService.OnPlayerDied(p)
                -- 15% of 1 = 0 floored, but minimum loss is 1
                assert(profile.ResonanceShards == 0,
                    "Should lose at least 1 Shard (was 1), got " .. tostring(profile.ResonanceShards))
            end,
        },

        {
            name = "OnPlayerDied: no-op when Shards are 0",
            fn = function()
                local p = makePlayer({ResonanceShards = 0, TotalResonance = 100})
                local profile = DataService:GetProfile(p)
                ProgressionService.OnPlayerDied(p)
                assert(profile.ResonanceShards == 0, "Shards stay 0 when already 0")
                assert(profile.TotalResonance == 100, "TotalResonance unchanged")
            end,
        },

        -- ─── SetPlayerRing ────────────────────────────────────────────────────

        {
            name = "SetPlayerRing: updates CurrentRing on profile",
            fn = function()
                local p = makePlayer({CurrentRing = 1})
                local profile = DataService:GetProfile(p)
                ProgressionService.SetPlayerRing(p, 2)
                assert(profile.CurrentRing == 2,
                    "CurrentRing should be 2, got " .. tostring(profile.CurrentRing))
            end,
        },

        {
            name = "SetPlayerRing: clamps out-of-range values to 0-5",
            fn = function()
                local p = makePlayer({CurrentRing = 1})
                local profile = DataService:GetProfile(p)
                ProgressionService.SetPlayerRing(p, 99)
                assert(profile.CurrentRing == 5,
                    "Ring 99 should clamp to 5, got " .. tostring(profile.CurrentRing))
                ProgressionService.SetPlayerRing(p, -3)
                assert(profile.CurrentRing == 0,
                    "Ring -3 should clamp to 0, got " .. tostring(profile.CurrentRing))
            end,
        },

        -- ─── SelectDiscipline ─────────────────────────────────────────────────

        {
            name = "SelectDiscipline: valid choice locks in DisciplineId",
            fn = function()
                local p = makePlayer({HasChosenDiscipline = false, DisciplineId = "Wayward"})
                local profile = DataService:GetProfile(p)
                local ok, err = ProgressionService.SelectDiscipline(p, "Ironclad")
                assert(ok == true, "Expected success, got: " .. tostring(err))
                assert(profile.DisciplineId == "Ironclad",
                    "DisciplineId should be Ironclad, got " .. tostring(profile.DisciplineId))
                assert(profile.HasChosenDiscipline == true,
                    "HasChosenDiscipline should be true")
            end,
        },

        {
            name = "SelectDiscipline: invalid id is rejected",
            fn = function()
                local p = makePlayer({HasChosenDiscipline = false})
                local ok, reason = ProgressionService.SelectDiscipline(p, "WizardOfOz")
                assert(ok == false, "Should reject invalid discipline")
                assert(reason == "InvalidDiscipline",
                    "Reason should be InvalidDiscipline, got " .. tostring(reason))
            end,
        },

        {
            name = "SelectDiscipline: second selection is rejected (one-time only)",
            fn = function()
                local p = makePlayer({HasChosenDiscipline = false})
                ProgressionService.SelectDiscipline(p, "Silhouette")
        -- ─── ProgressionTypes constants ───────────────────────────────────────

        {
            name = "ProgressionTypes: RING_CONFIGS has entries for rings 0-5",
            fn = function()
                for i = 0, 5 do
                    assert(RING_CONFIGS[i] ~= nil,
                        ("RING_CONFIGS missing entry for ring %d"):format(i))
                end
            end,
        },

        {
            name = "ProgressionTypes: RING_CONFIGS diminish thresholds match design doc",
            fn = function()
                assert(RING_CONFIGS[1].DiminishThreshold == 0.75, "Ring 1 should diminish at 75%")
                assert(RING_CONFIGS[2].DiminishThreshold == 0.80, "Ring 2 should diminish at 80%")
                assert(RING_CONFIGS[3].DiminishThreshold == 0.82, "Ring 3 should diminish at 82%")
                assert(RING_CONFIGS[4].DiminishThreshold == 0.85, "Ring 4 should diminish at 85%")
            end,
        },

        {
            name = "ProgressionTypes: VALID_STAT_NAMES includes all six stats",
            fn = function()
                for _, statName in ipairs({"Strength", "Fortitude", "Agility", "Intelligence", "Willpower", "Charisma"}) do
                    assert(VALID_STAT_NAMES[statName],
                        ("Missing stat in VALID_STAT_NAMES: %s"):format(statName))
                end
            end,
        },

        {
            name = "ProgressionTypes: STAT_POINT_MILESTONE is 200",
            fn = function()
                assert(STAT_POINT_MILESTONE == 200,
                    "STAT_POINT_MILESTONE should be 200, got " .. tostring(STAT_POINT_MILESTONE))
            end,
        },

        {
            name = "ProgressionTypes: STAT_MAX_PER_STAT is 20",
            fn = function()
                assert(STAT_MAX_PER_STAT == 20,
                    "STAT_MAX_PER_STAT should be 20, got " .. tostring(STAT_MAX_PER_STAT))
            end,
        },

    },
}
