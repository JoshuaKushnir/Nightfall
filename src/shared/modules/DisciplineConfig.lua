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
