--!strict
-- DisciplineConfig
-- Contains numeric balancing values for each Discipline.
-- Accessible from server and client; lightweight lookups only.

local DisciplineConfig: {[string]: any} = {
    --
    -- Each Discipline table defines the *base numeric values* that drive all of
    -- the combat subsystems.  Values here are the single source of truth; no
    -- other module should hardcode numbers.  All numbers are proposed (✏️) and
    -- remain open for tuning.
    --

    Wayward = {
        -- Breath system ----------------------------------------------------
        breathPool = 100,          -- medium pool, ✏️ keeps the 0-100 scale familiar
        breathDrainSprint = 10,    -- average drain rate while sprinting
        breathDrainDash = 15,      -- standard cost per dash
        breathDrainWallRun = 20,   -- moderate cost; Wayward uses wallrun some
                                   -- but not as often as Silhouette
        breathRegenGrounded = 30,  -- average regen when standing still

        -- Posture system --------------------------------------------------
        postureMax = 100,          -- medium posture ceiling
        postureRecovery = 6,       -- average points recovered/sec when not staggered
        postureBlockMultiplier = 1.0, -- baseline block efficiency (no bonus/penalty)
        staggerDuration = 0.8,     -- medium stagger lock (seconds)

        -- Weapon access ---------------------------------------------------
        weaponClasses = {"Light", "Medium"}, -- balanced toolbox

        -- Aspect scaling (shape reserve; populated later by Aspect team)
        -- aspectScaling = { expression = nil, form = nil, communion = nil },
    },

    Ironclad = {
        -- Breath ----------------------------------------------------------------
        breathPool = 90,           -- low-end pool, Ironclad plods through breath
        breathDrainSprint = 12,    -- worst efficiency to punish mobility abuse
        breathDrainDash = 18,
        breathDrainWallRun = 22,
        breathRegenGrounded = 25,  -- slow regen; encourages deliberate play

        -- Posture ----------------------------------------------------------------
        postureMax = 120,          -- high posture cap representing endurance
        postureRecovery = 5,       -- slower recovery; Tempered Stance is the real
                                   -- recovery mechanic
        postureBlockMultiplier = 0.75, -- 25% drain reduction when holding block
        staggerDuration = 0.9,     -- long lock; compensated by passive below

        -- Weapon access -------------------------------------------------------
        weaponClasses = {"Light","Medium","Heavy"},

        -- aspectScaling = { expression = nil, form = nil, communion = nil },

        -- Tempered Stance passive ------------------------------------------------
        -- Ironclad builds up 'Poise' as a fight drags on. Poise grants HP
        -- damage reduction and makes it harder to be staggered/lose posture
        -- when blocking.  See Section 2a design docs for complete rules.
        temperedStance = {
            accumulation = {
                perHit = 1,         -- points gained on every hit received (blocked or not)
                perBlock = 2,       -- additional points for successfully blocking a hit
                cap = 30,           -- maximum stored Poise across a single engagement
                decayDelay = 10,    -- seconds out of combat before Poise begins to fall
                decayRate = 1,      -- points per second once decay starts
            },
            tiers = {
                {
                    threshold = 10,            -- Tier 1 when Poise >= 10
                    hpDamageReduction = 0.05,  -- 5% less HP damage taken
                    blockDrainReduction = 0.10,-- 10% less posture drained when blocking
                    state = "Tempered1",      -- StateService enum to broadcast
                },
                {
                    threshold = 20,            -- Tier 2
                    hpDamageReduction = 0.10,
                    blockDrainReduction = 0.20,
                    state = "Tempered2",
                },
                {
                    threshold = 30,            -- Tier 3 (maxed)
                    hpDamageReduction = 0.15,
                    blockDrainReduction = 0.30,
                    state = "Tempered3",
                },
            },
            reset = {
                onStaggerDropTiers = 1, -- losing a stagger removes one tier (subtract
                                        -- corresponding threshold points)
                onBreak = "full",     -- fully resets Poise and tiers on Break or death
                onDeath = "full",
            },
            clash = {
                tier2CounterBonus = 0.10, -- during CLASH_WINDOW, Tier2+ counter-strike
                                           -- deals +10% posture damage
                tier3InstantBreak = true, -- at Tier3 a successful counter can immediately
                                           -- trigger a Break (posture permitting)
            },
        },
    },

    Silhouette = {
        -- Breath ----------------------------------------------------------------
        breathPool = 110,          -- highest breath reservoir for dash heavy play
        breathDrainSprint = 8,     -- best efficiency to reward constant motion
        breathDrainDash = 12,
        breathDrainWallRun = 16,
        breathRegenGrounded = 35,  -- fastest regen of the four disciplines

        -- Posture ----------------------------------------------------------------
        postureMax = 80,           -- low posture makes avoiding hits critical
        postureRecovery = 7,       -- fastest recovery rate to bounce back quickly
        postureBlockMultiplier = 1.25, -- penalty on blocked damage to discourage
                                       -- passive walls
        staggerDuration = 0.6,     -- short window to reset the rhythm

        -- Weapon access -------------------------------------------------------
        weaponClasses = {"Light"}, -- speed‑oriented gear only

        -- aspectScaling = { expression = nil, form = nil, communion = nil },
    },

    Resonant = {
        -- Breath ----------------------------------------------------------------
        breathPool = 95,           -- medium‑low pool; Resonant leans on precision
        breathDrainSprint = 11,    -- average efficiency
        breathDrainDash = 16,
        breathDrainWallRun = 20,
        breathRegenGrounded = 30,  -- middling regen rate

        -- Posture ----------------------------------------------------------------
        postureMax = 90,           -- low‑medium cap to reflect lower physical
                                   -- sturdiness
        postureRecovery = 6,       -- average recovery
        postureBlockMultiplier = 1.0,-- neutral; no bonus or penalty
        staggerDuration = 0.8,     -- medium lock duration

        -- Weapon access -------------------------------------------------------
        weaponClasses = {"Light","Medium"},

        -- aspectScaling = { expression = nil, form = nil, communion = nil },
    },
}

-- fallback accessor
local function Get(id: string)
	return DisciplineConfig[id] or DisciplineConfig.Wayward
end

return {
	Get = Get,
	Raw = DisciplineConfig,
}
