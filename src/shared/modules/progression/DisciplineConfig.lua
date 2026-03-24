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

        -- Break damage modifiers ------------------------------------------
        breakBase = 45,            -- base HP damage on a Break
        breakOverflowMult = 1.0,   -- extra HP per overflow posture point

        -- Weapon access ---------------------------------------------------
        weaponClasses = {"Light", "Medium"}, -- balanced toolbox

        -- Wayward passive: Steady Ground -----------------------------------
        -- Composure builds passively during any active engagement and only
        -- affects penalty states.  It is invisible during normal play but
        -- subtly reduces the pain of being pushed around.
        steadyGround = {
            accumulationRate = 1,      -- composure points per second in combat
            cap = 20,                  -- maximum composure stored
            combatTimeout = 5,         -- seconds of no combat before reset begins
            decayRate = 2,             -- composure points lost per second out of combat
            effects = {
                staggerDurationReductionPer = 0.01, -- 1% shorter stagger per point
                staggerDrainReductionPer = 0.01,    -- 1% less posture drain per point
                shardLossReductionPer = 1,          -- 1 less shard lost on death per point
                dimmingDurationReductionPer = 0.02, -- 2% shorter Dimming debuff per point
            },
            visualState = "SteadyGroundActive", -- faint aura state broadcast when >0
            crossTrain = {
                accumulationRate = 0.5,  -- slower earn rate
                cap = 10,                -- lower maximum
                effects = {
                    staggerDurationReductionPer = 0.005,
                    staggerDrainReductionPer = 0.005,
                    shardLossReductionPer = 0.5,
                    dimmingDurationReductionPer = 0.01,
                },
            },
        },

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

        -- Break modifiers ----------------------------------------------------
        breakBase = 40,            -- slightly lower base damage
        breakOverflowMult = 0.9,   -- Ironclad overflow less effective

        -- Weapon access -------------------------------------------------------
        weaponClasses = {"Light","Medium","Heavy"},

        -- aspectScaling = { expression = nil, form = nil, communion = nil },
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
            crossTrain = {
                -- Cross-training grants the first tier only: a small flat stagger
                -- resistance bonus (5%) with no accumulation mechanic.
                flatStaggerReduction = 0.05,
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

        -- Break modifiers ----------------------------------------------------
        breakBase = 50,            -- high baseline to reward speed
        breakOverflowMult = 1.1,   -- bigger bonus from overflow

        -- Weapon access -------------------------------------------------------
        weaponClasses = {"Light"}, -- speed‑oriented gear only

        -- Ghoststep passive ----------------------------------------------------
        -- Silhouette dashes have reduced recovery and can chain; the core of
        -- her Clash pressure.  See Section 2b design for details.
        ghoststep = {
            baseRecoveryFrames = 18,          -- ~0.30s at 60fps
            reductionPerDash = {8, 6, 4},     -- frames removed for dash 1/2/3
            chainCap = 3,                     -- after 3 dashes passive pauses
            cooldownAfterCap = 1.0,           -- seconds before Ghoststep returns
            clashWindowBonus = 0.1,           -- +100ms extra time to react inside
                                               -- CLASH_WINDOW for Silhouette
            crossTrain = {
                reductionFrames = 4,         -- only first dash gets -4 frames
                appliesTo = 1,               -- does not sustain through chains
            },
        },

        -- aspectScaling = { expression = nil, form = nil, communion = nil },
    },

    -- Global cross-training penalties applied when a player uses a weapon
    -- outside their primary Discipline (Section 6c).
    crossTrainPenalty = {
        hpDamageMult = 0.85,      -- 15% less HP damage with cross-trained weapons
        postureDamageMult = 0.9,  -- 10% less posture damage
        breathCostMult = 1.15,    -- 15% more breath cost
        attackSpeedMult = 0.95,   -- slightly slower swings
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

        -- Break modifiers ----------------------------------------------------
        breakBase = 45,            -- standard base value
        breakOverflowMult = 1.0,   -- no special bonus

        -- Weapon access -------------------------------------------------------
        weaponClasses = {"Light","Medium"},

        -- Resonant passive: Cadence Strike -----------------------------------
        -- Tempo builds when attacks land cleanly; breaking rhythm costs tempo.
        -- Tempo only affects posture damage (no HP boost).  Full tempo
        -- allows Resonant to open Break windows as efficiently as Ironclad.
        cadenceStrike = {
            accumulation = {
                perHit = 5,       -- points gained per successful posture-hitting attack
                cap = 100,        -- maximum tempo
                breakPenalty = 50,-- tempo lost instantly when cadence is broken
                decayRate = 10,   -- tempo points lost per second after a break
            },
            multiplierAtFull = 2.0, -- posture damage multiplier when tempo == cap
            tiers = {25, 50, 75, 100}, -- breakpoints for visual states
            visualStates = {"Cadence0","Cadence1","Cadence2","Cadence3"},
            clash = {
                -- counters while at full tempo apply the same multiplier;
                -- this is how Resonant "creates Break windows as efficiently as
                -- an Ironclad".
                fullTempoCounterMult = 2.0,
            },
            crossTrain = {
                perHit = 2.5,          -- slower build
                cap = 50,              -- lower ceiling
                multiplierAtFull = 1.25,-- mild posture bonus only
            },
        },

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
