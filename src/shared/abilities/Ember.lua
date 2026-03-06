--!strict
--[[
    Class: Ember
    Description: EMBER — Stack-based escalation, aggressive commitment.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Highest ceiling for sustained damage. Heat stacks on the
                 opponent and Momentum working together create compounding pressure.
    Issue: #149 — refactor Aspect system to full moveset
    Dependencies: none (server-only via OnActivate)

    Move list:
        [1] Ignite      (UtilityProc) — Stack builder / initiator
        [2] Flashfire   (Offensive)   — AoE stack detonation / payoff
        [3] HeatShield  (Defensive)   — Absorb hits → generate stacks
        [4] Surge       (SelfBuff)    — Momentum amplifier / aggression burst
        [5] CinderField (UtilityProc) — Area control / sustained stack pressure
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- ═════════════════════════════════════════════════════════════════════════════
-- HEAT STACK SYSTEM CONSTANTS
-- ═════════════════════════════════════════════════════════════════════════════

local HEAT_STACK_MAX         : number = 3
local HEAT_STACK_DECAY_TIME  : number = 6    -- seconds before stacks expire
local BURNING_HP_PER_SEC     : number = 5    -- HP drain while Burning
local BURNING_DURATION       : number = 4    -- seconds of Burning at max stacks

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 1 — IGNITE  (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════

local IGNITE_DASH_DIST      : number = 8
local IGNITE_POSTURE_PER_HEAT: number = 15
local IGNITE_HIT_RADIUS     : number = 5

-- VFX STUB — animator: ember-trail dash + ground-ring burst at landing
local function _VFX_Ignite_Dash(_origin: Vector3, _dest: Vector3) end
local function _VFX_Ignite_Impact(_pos: Vector3, _stacks: number) end
-- VFX STUB — animator: persistent flame shimmer on character while Burning
local function _VFX_BurningStatus(_char: Model) end

local function _applyHeatStack(target: any, char: Model, stacks: number, casterName: string)
    local currentStacks = (char:GetAttribute("HeatStacks") :: number?) or 0
    local newStacks = math.min(HEAT_STACK_MAX, currentStacks + stacks)
    char:SetAttribute("HeatStacks", newStacks)

    -- Posture damage per stack applied
    local postureDmg = IGNITE_POSTURE_PER_HEAT * stacks
    char:SetAttribute("IncomingPostureDamage",
        (char:GetAttribute("IncomingPostureDamage") or 0) + postureDmg)
    char:SetAttribute("IncomingPostureDamageSource", casterName .. "_Ignite")

    -- Refresh stack decay timer
    char:SetAttribute("HeatStackExpiry", tick() + HEAT_STACK_DECAY_TIME)

    -- Trigger Burning at max stacks
    if newStacks >= HEAT_STACK_MAX then
        char:SetAttribute("StatusBurning", true)
        char:SetAttribute("BurningExpiry", tick() + BURNING_DURATION)
        char:SetAttribute("BurningHPPerSecond", BURNING_HP_PER_SEC)
        _VFX_BurningStatus(char)
        task.delay(BURNING_DURATION, function()
            if char and char.Parent then
                local expiry = (char:GetAttribute("BurningExpiry") :: number?) or 0
                if tick() >= expiry then
                    char:SetAttribute("StatusBurning", nil)
                    char:SetAttribute("BurningExpiry", nil)
                    char:SetAttribute("BurningHPPerSecond", nil)
                end
            end
        end)
    end

    -- Decay stacks after HEAT_STACK_DECAY_TIME if not refreshed
    task.delay(HEAT_STACK_DECAY_TIME, function()
        if not char or not char.Parent then return end
        local expiry = (char:GetAttribute("HeatStackExpiry") :: number?) or 0
        if tick() >= expiry then
            char:SetAttribute("HeatStacks", 0)
            char:SetAttribute("HeatStackExpiry", nil)
        end
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 2 — FLASHFIRE  (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.15s cast. 5-stud sphere burst. 20 posture to all targets. Consumes all
--  Heat stacks: +8 HP per stack. Overheat (2s): mana regen paused, melee +20%.

local FLASHFIRE_RADIUS       : number = 5
local FLASHFIRE_POSTURE_DMG  : number = 20
local FLASHFIRE_HP_PER_STACK : number = 8
local FLASHFIRE_OVERHEAT_DUR : number = 2

-- VFX STUB — animator: radial orange-white heat burst, scorched ground ring
local function _VFX_Flashfire(_pos: Vector3, _stacks: number) end
-- VFX STUB — animator: heat shimmer aura around caster during Overheat
local function _VFX_Overheat_Enter(_caster: Player) end
local function _VFX_Overheat_Exit(_caster: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 3 — HEAT SHIELD  (Defensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.1s cast. 1.5s: convert incoming HP damage → Posture at 150% rate.
--  On expiry: restore 1 stack per hit absorbed (max 3 stacks to caster).

local HEAT_SHIELD_DURATION      : number = 1.5
local HEAT_SHIELD_POSTURE_MULT  : number = 1.5
local HEAT_SHIELD_STACK_MAX     : number = 3

-- VFX STUB — animator: ember/red energy field around caster, crinkles on each absorbed hit
local function _VFX_HeatShield_Enter(_caster: Player) end
local function _VFX_HeatShield_Exit(_caster: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 4 — SURGE  (SelfBuff)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.25s cast. +1 Momentum stack immediately. 4s sprint speed boost (+3 studs/s).
--  First melee hit within window applies 1 Heat stack automatically.
--  Speed boost cancelled on taking damage.

local SURGE_DURATION        : number = 4
local SURGE_SPEED_BONUS     : number = 3  -- studs/s

-- VFX STUB — animator: ember aura around legs during sprint boost, fades on damage
local function _VFX_Surge_Enter(_caster: Player) end
local function _VFX_Surge_Exit(_caster: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 5 — CINDER FIELD  (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.3s cast. 6-stud radius ember field around caster for 6s. Targets inside:
--  4 HP/s drain + 1 Heat stack per 2s. Field does not follow caster.

local CINDER_FIELD_RADIUS   : number = 6
local CINDER_FIELD_DURATION : number = 6
local CINDER_FIELD_HP_PER_S : number = 4
local CINDER_FIELD_STACK_INTERVAL: number = 2  -- seconds between stack applications

-- VFX STUB — animator: ground-level ember glow zone, constantly flickering embers rising
local function _VFX_CinderField_Create(_pos: Vector3, _radius: number) end
local function _VFX_CinderField_Expire(_pos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVESET MODULE
-- ═════════════════════════════════════════════════════════════════════════════

local Ember = {
    AspectId    = "Ember",
    DisplayName = "Ember",
    Moves = {} :: any,
}

-- ── Move 1 ───────────────────────────────────────────────────────────────────
Ember.Moves[1] = {
    Id          = "Ignite",
    Name        = "Ignite",
    AspectId    = "Ember",
    Slot        = 1,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Charge forward 8 studs. On contact: 1 Heat stack + 15 posture damage. "
                .. "At 3 stacks: Burning (5 HP/s for 4s, Posture recovery halved). "
                .. "At 2× Momentum: apply 2 stacks instead. Shortest cooldown in kit.",

    CastTime         = 0.2,
    ManaCost         = 20,
    Cooldown         = 5,
    Range            = IGNITE_DASH_DIST,
    PostureDamage    = IGNITE_POSTURE_PER_HEAT,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "HeatTransfer",
            Name          = "Heat Transfer",
            InteractsWith = "Burning",
            Description   = "If target is already Burning when hit by Ignite, Ignite reapplies "
                          .. "and resets Burning duration to 4s instead of stacking higher. "
                          .. "Maintains Burning against recovery builds.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Burning check at hit time
        },
        {
            Id            = "Torch",
            Name          = "Torch",
            InteractsWith = "Momentum",
            Description   = "At 2× Momentum, Ignite applies 2 Heat stacks instead of 1. "
                          .. "Movement investment rewarded with double stack pressure.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum threshold check
        },
        {
            Id            = "IgnitionChain",
            Name          = "Ignition Chain",
            InteractsWith = "Airborne",
            Description   = "If Ignite connects mid-air (both airborne), neither takes knockback "
                          .. "from the collision — both continue moving. Aerial combo-extender.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne detection for both players
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        local dest = root.Position + root.CFrame.LookVector * IGNITE_DASH_DIST
        _VFX_Ignite_Dash(root.Position, dest)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin      = root.Position
        local forward     = root.CFrame.LookVector
        local destination = origin + forward * IGNITE_DASH_DIST

        -- Determine stack count (Torch talent: 2× Momentum → 2 stacks)
        local momentum     = (root:GetAttribute("Momentum") :: number?) or 1
        local stacksToApply = 1
        -- TALENT HOOK STUB: Torch — at 2× Momentum apply 2 stacks
        if momentum >= 2 then
            -- Base behavior without talent: still 1 stack; talent changes this to 2
            -- stacksToApply = 2  ← enabled when talent is purchased
        end

        task.delay(0.2, function()
            if not char or not char.Parent then return end
            if not root or not root.Parent then return end
            root.CFrame = CFrame.new(destination, destination + forward)
            _VFX_Ignite_Dash(origin, destination)

            -- Use HitboxService for landing detection
            local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
            pcall(function()
                local PostureService = require(game:GetService("ServerScriptService").Server.services.PostureService)
                
                HitboxService.CreateHitbox({
                    Shape = "Sphere",
                    Owner = player,
                    Position = destination,
                    Size = Vector3.new(IGNITE_HIT_RADIUS, IGNITE_HIT_RADIUS, IGNITE_HIT_RADIUS),
                    Damage = 0,
                    LifeTime = 0.5,
                    CanHitTwice = false,
                    OnHit = function(hitTarget: any)
                        local tChar
                        if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                            tChar = hitTarget.Character
                        elseif type(hitTarget) == "string" then
                            local DummyService = require(game:GetService("ServerScriptService").Server.services.DummyService)
                            tChar = DummyService:GetDummyModel(hitTarget)
                        end
                        if not tChar then return end

                        PostureService.DrainPosture(hitTarget, IGNITE_POSTURE_PER_HEAT * stacksToApply, "Aspect")
                        _applyHeatStack(hitTarget, tChar, stacksToApply, player.Name)
                        _VFX_Ignite_Impact(destination, stacksToApply)
                    end
                })
            end)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Ignite", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 2 ───────────────────────────────────────────────────────────────────
Ember.Moves[2] = {
    Id          = "Flashfire",
    Name        = "Flashfire",
    AspectId    = "Ember",
    Slot        = 2,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "Release heat burst in 5-stud sphere. 20 posture to all targets. "
                .. "Consumes all Heat stacks: +8 HP per stack consumed. "
                .. "Overheat 2s after cast: mana regen paused, melee +20%.",

    CastTime         = 0.15,
    ManaCost         = 25,
    Cooldown         = 10,
    Range            = FLASHFIRE_RADIUS,
    PostureDamage    = FLASHFIRE_POSTURE_DMG,
    BaseDamage       = nil,  -- HP damage is stack-dependent, not a flat value
    IsAoE            = true,
    RequiredState    = {"Idle", "Walking", "Running", "Attacking"},

    Talents = {
        {
            Id            = "Flashpoint",
            Name          = "Flashpoint",
            InteractsWith = "Momentum",
            Description   = "At 3× Momentum, Flashfire radius increases to 8 studs and Overheat "
                          .. "extends to 3.5s. Highest-risk version → highest-reward.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum check + radius override
        },
        {
            Id            = "ScorchMark",
            Name          = "Scorch Mark",
            InteractsWith = "Saturated",
            Description   = "Flashfire creates a 4-stud burning ground tile for 5s. Saturated "
                          .. "targets entering gain Burning. Connects with Tide cross-interaction.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires burning zone creation
        },
        {
            Id            = "ThermalFeedback",
            Name          = "Thermal Feedback",
            InteractsWith = "Posture",
            Description   = "During Overheat, blocked hits drain an extra +10 Posture per hit "
                          .. "(normally blocked hits drain 0 HP). Makes Overheat attacks punish blocking.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires block event hook during Overheat
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_Flashfire(root.Position, 0)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin = root.Position

        -- Check Momentum for Flashpoint talent (radius stays base without it)
        local radius = FLASHFIRE_RADIUS
        local overheatDur = FLASHFIRE_OVERHEAT_DUR
        -- TALENT HOOK STUB: Flashpoint — at 3× Momentum, radius = 8, overheatDur = 3.5

        -- AoE hit detection
        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        pcall(function()
            HitboxService.CreateHitbox({
                Shape = "Sphere",
                Owner = player,
                Position = origin,
                Size = Vector3.new(radius, radius, radius),
                Damage = 0,
                LifeTime = 0.5,
                CanHitTwice = false,
                OnHit = function(hitTarget: any)
                    local tChar
                    if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                        tChar = hitTarget.Character
                    elseif type(hitTarget) == "string" then
                        local DummyService = require(game:GetService("ServerScriptService").Server.services.DummyService)
                        tChar = DummyService:GetDummyModel(hitTarget)
                    end
                    if not tChar then return end

                    -- Posture damage
                    tChar:SetAttribute("IncomingPostureDamage",
                        (tChar:GetAttribute("IncomingPostureDamage") or 0) + FLASHFIRE_POSTURE_DMG)
                    tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_Flashfire")

                    -- Consume Heat stacks → HP damage
                    local stacks = (tChar:GetAttribute("HeatStacks") :: number?) or 0
                    if stacks > 0 then
                        local hpDmg = stacks * FLASHFIRE_HP_PER_STACK
                        tChar:SetAttribute("IncomingHPDamage",
                            (tChar:GetAttribute("IncomingHPDamage") or 0) + hpDmg)
                        tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_FlashfireStacks")
                        tChar:SetAttribute("HeatStacks", 0)
                        tChar:SetAttribute("HeatStackExpiry", nil)
                    end
                    -- TALENT HOOK STUB: ScorchMark — create burning ground tile at origin
                end
            })
        end)

        _VFX_Flashfire(origin, 0)

        -- Overheat state
        char:SetAttribute("StatusOverheat", true)
        char:SetAttribute("OverheatExpiry", tick() + overheatDur)
        _VFX_Overheat_Enter(player)
        task.delay(overheatDur, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusOverheat", nil)
            char:SetAttribute("OverheatExpiry", nil)
            _VFX_Overheat_Exit(player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Flashfire", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 3 ───────────────────────────────────────────────────────────────────
Ember.Moves[3] = {
    Id          = "HeatShield",
    Name        = "Heat Shield",
    AspectId    = "Ember",
    Slot        = 3,
    Type        = "Expression",
    MoveType    = "Defensive",
    Description = "For 1.5s, convert incoming HP damage → Posture at 150% rate. "
                .. "On expiry: restore 1 Heat stack per hit absorbed (max 3). "
                .. "Can be Staggered through at 150% posture drain.",

    CastTime         = 0.1,
    ManaCost         = 20,
    Cooldown         = 12,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping"},

    Talents = {
        {
            Id            = "ReturnFire",
            Name          = "Return Fire",
            InteractsWith = "Heat Stacks",
            Description   = "If Heat Shield absorbs 3 hits and converts all 3 to stacks, on expiry "
                          .. "you release an Ignite-equivalent pulse (no mana, no cooldown). "
                          .. "Absorbed pressure becomes instant offense.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires 3-hit counter check + free Ignite pulse
        },
        {
            Id            = "EmberArmor",
            Name          = "Ember Armor",
            InteractsWith = "Burning (self)",
            Description   = "While Heat Shield is active, if you are Burning, the Burning HP drain "
                          .. "is paused. The defensive window also clears your own debuff timer.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Burning pause flag during shield
        },
        {
            Id            = "ThermalMass",
            Name          = "Thermal Mass",
            InteractsWith = "Airborne",
            Description   = "Heat Shield can be cast while airborne. If cast airborne, absorbed "
                          .. "hits convert to a single 4-stud burst on landing (no stack consumption).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne state + landing event hook
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_HeatShield_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end

        char:SetAttribute("StatusHeatShield", true)
        char:SetAttribute("HeatShieldExpiry", tick() + HEAT_SHIELD_DURATION)
        char:SetAttribute("HeatShieldHitsAbsorbed", 0)
        _VFX_HeatShield_Enter(player)

        -- TALENT HOOK STUB: EmberArmor — pause Burning HP drain for duration
        -- TALENT HOOK STUB: ThermalMass — if airborne, store hits for landing burst

        task.delay(HEAT_SHIELD_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusHeatShield", nil)
            char:SetAttribute("HeatShieldExpiry", nil)

            local absorbed = (char:GetAttribute("HeatShieldHitsAbsorbed") :: number?) or 0
            char:SetAttribute("HeatShieldHitsAbsorbed", nil)

            -- Give caster stacks per absorbed hit
            local stacksGained = math.min(absorbed, HEAT_SHIELD_STACK_MAX)
            if stacksGained > 0 then
                local currentStacks = (char:GetAttribute("HeatStacks") :: number?) or 0
                char:SetAttribute("HeatStacks", math.min(HEAT_STACK_MAX, currentStacks + stacksGained))
                char:SetAttribute("HeatStackExpiry", tick() + HEAT_STACK_DECAY_TIME)
                -- TALENT HOOK STUB: ReturnFire — if absorbed == 3, release free Ignite pulse
            end

            _VFX_HeatShield_Exit(player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "HeatShield", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 4 ───────────────────────────────────────────────────────────────────
Ember.Moves[4] = {
    Id          = "Surge",
    Name        = "Surge",
    AspectId    = "Ember",
    Slot        = 4,
    Type        = "Expression",
    MoveType    = "SelfBuff",
    Description = "+1 Momentum stack immediately. 4s sprint speed boost (+3 studs/s). "
                .. "First melee hit in window applies 1 Heat stack automatically. "
                .. "Speed boost cancelled on taking damage. Best opener in kit.",

    CastTime         = 0.25,
    ManaCost         = 25,
    Cooldown         = 14,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "SurgeFeint",
            Name          = "Surge Feint",
            InteractsWith = "Feinting",
            Description   = "Surge's speed window allows melee feints to apply Dampened to opponent "
                          .. "(Momentum reset) instead of just cancelling your own attack. "
                          .. "Turns the fake-out into a debuff.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires feint → Dampened hook during Surge state
        },
        {
            Id            = "Accelerant",
            Name          = "Accelerant",
            InteractsWith = "Breath",
            Description   = "Surge restores 15 Breath on activation. Enables movement burst "
                          .. "immediately — sprint out of a bad position into a new angle.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Breath attribute restore on cast
        },
        {
            Id            = "BurningApproach",
            Name          = "Burning Approach",
            InteractsWith = "Burning",
            Description   = "If Surge is activated while a target within 8 studs is Burning, "
                          .. "you gain 2 Momentum stacks instead of 1. Rewards pressured targets.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires nearby Burning target detection at cast
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_Surge_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Player?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- +1 Momentum stack
        local currentMomentum = (root:GetAttribute("Momentum") :: number?) or 1
        root:SetAttribute("Momentum", math.min(3, currentMomentum + 1))

        -- TALENT HOOK STUB: BurningApproach — if nearby Burning target, +2 stacks instead
        -- TALENT HOOK STUB: Accelerant — restore 15 Breath

        -- Surge active state
        char:SetAttribute("StatusSurge", true)
        char:SetAttribute("SurgeExpiry", tick() + SURGE_DURATION)
        char:SetAttribute("SurgeFirstHitReady", true)  -- CombatService reads: first hit gets free stack
        _VFX_Surge_Enter(player)

        -- TALENT HOOK STUB: SurgeFeint — during state, feints apply Dampened

        task.delay(SURGE_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusSurge", nil)
            char:SetAttribute("SurgeExpiry", nil)
            char:SetAttribute("SurgeFirstHitReady", nil)
            _VFX_Surge_Exit(player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Surge", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 5 ───────────────────────────────────────────────────────────────────
Ember.Moves[5] = {
    Id          = "CinderField",
    Name        = "Cinder Field",
    AspectId    = "Ember",
    Slot        = 5,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Coat a 6-stud radius around current position in embers for 6s. "
                .. "Targets inside: 4 HP/s drain, +1 Heat stack per 2s. "
                .. "Field does not follow caster. Allies unaffected.",

    CastTime         = 0.3,
    ManaCost         = 30,
    Cooldown         = 16,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "Bonfire",
            Name          = "Bonfire",
            InteractsWith = "Burning",
            Description   = "Targets inside Cinder Field who reach the 3-stack threshold and become "
                          .. "Burning gain Grounded for 2s at that moment. Combustion = rooted.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Burning trigger hook in heat stack system
        },
        {
            Id            = "HeatSink",
            Name          = "Heat Sink",
            InteractsWith = "Overheat",
            Description   = "If Flashfire is cast while standing in your own Cinder Field, Overheat "
                          .. "duration extends from 2s to 5s. Cinder Field becomes a Flashfire amplifier.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires zone check at Flashfire cast time
        },
        {
            Id            = "Draft",
            Name          = "Draft",
            InteractsWith = "Airborne + Gale synergy",
            Description   = "Cinder Field creates an upward thermal column. You and allies in the "
                          .. "field gain slightly increased jump height. Ember/Gale cross-build interaction.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires jump height modifier in MovementService
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_CinderField_Create(root.Position, CINDER_FIELD_RADIUS)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local fieldCenter = root.Position

        -- Create zone Part
        local zonePart = Instance.new("Part")
        zonePart.Name         = "EmberCinderFieldZone"
        zonePart.Anchored     = true
        zonePart.CanCollide   = false
        zonePart.Transparency = 1
        zonePart.Size         = Vector3.new(CINDER_FIELD_RADIUS * 2, 0.5, CINDER_FIELD_RADIUS * 2)
        zonePart.CFrame       = CFrame.new(fieldCenter)
        zonePart:SetAttribute("ZoneOwner", player.Name)
        zonePart:SetAttribute("ZoneType", "EmberCinderField")
        zonePart:SetAttribute("ZoneExpiry", tick() + CINDER_FIELD_DURATION)
        zonePart.Parent       = Workspace

        _VFX_CinderField_Create(fieldCenter, CINDER_FIELD_RADIUS)

        -- Periodic damage + stack application to targets inside zone
        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        local DummyService = pcall(function() return require(game:GetService("ServerScriptService").Server.services.DummyService) end) and require(game:GetService("ServerScriptService").Server.services.DummyService) or nil

        local elapsed = 0
        local stackTimer = 0
        local function _tick(dt: number)
            elapsed += dt
            stackTimer += dt
            if elapsed >= CINDER_FIELD_DURATION then
                return true  -- done
            end
            
            pcall(function()
                HitboxService.CreateHitbox({
                    Shape = "Cylinder",
                    Owner = player,
                    Position = fieldCenter,
                    Size = Vector3.new(CINDER_FIELD_RADIUS, 10, CINDER_FIELD_RADIUS),
                    Damage = 0,
                    LifeTime = 0.1,  -- just a single tick
                    CanHitTwice = false,
                    OnHit = function(hitTarget: any)
                        local tChar
                        if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                            tChar = hitTarget.Character
                        elseif type(hitTarget) == "string" and DummyService then
                            tChar = DummyService:GetDummyModel(hitTarget)
                        end
                        if not tChar then return end

                        -- HP drain per tick
                        tChar:SetAttribute("IncomingHPDamage",
                            (tChar:GetAttribute("IncomingHPDamage") or 0) + CINDER_FIELD_HP_PER_S * dt)
                        tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_CinderFieldDOT")
                        -- Heat stack per interval
                        if stackTimer >= CINDER_FIELD_STACK_INTERVAL then
                            _applyHeatStack(hitTarget, tChar, 1, player.Name)
                            -- TALENT HOOK STUB: Bonfire — if reached 3 stacks, apply Grounded 2s
                        end
                    end
                })
            end)
            
            if stackTimer >= CINDER_FIELD_STACK_INTERVAL then
                stackTimer -= CINDER_FIELD_STACK_INTERVAL
            end
            return false
        end

        -- Drive via task.delay steps (simple polling every 0.1s)
        local function _runField()
            local start = tick()
            while tick() - start < CINDER_FIELD_DURATION do
                local dt = 0.1
                local done = _tick(dt)
                if done then break end
                task.wait(dt)
            end
            if zonePart and zonePart.Parent then
                _VFX_CinderField_Expire(fieldCenter)
                zonePart:Destroy()
            end
        end
        task.spawn(_runField)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "CinderField", TargetPosition = targetPosition }) end
    end,
}



-- ─── VFX stubs ───────────────────────────────────────────────────────────────

local function _VFX_EmberDash(_origin: Vector3, _dest: Vector3)
    -- VFX STUB — animator: ember/fire particle trail along dash path
end

local function _VFX_IgniteImpact(_pos: Vector3, _stacks: number)
    -- VFX STUB — animator: ground-ring burst at landing, intensity scales with stacks
end

local function _VFX_BurningStatus(_char: Model)
    -- VFX STUB — animator: persistent flame shimmer on character while Burning
end

-- ─── Heat stack helper ───────────────────────────────────────────────────────

--[[
    _applyHeatStack(target, char, stacks, casterName)
    Increments the target's HeatStacks attribute and applies or refreshes the Burning status.
    PostureService/CombatService reads HeatStacks as a damage amplifier.
--]]
local function _applyHeatStack(target: Player, char: Model, stacks: number, casterName: string)
    local currentStacks = (char:GetAttribute("HeatStacks") :: number?) or 0
    local newStacks     = currentStacks + stacks
    char:SetAttribute("HeatStacks", newStacks)

    -- Posture damage: POSTURE_PER_HEAT per stack
    local postureDmg = POSTURE_PER_HEAT * stacks
    char:SetAttribute("IncomingPostureDamage",
        (char:GetAttribute("IncomingPostureDamage") or 0) + postureDmg)
    char:SetAttribute("IncomingPostureDamageSource", casterName .. "_Ignite")

    -- Apply / refresh Burning status
    char:SetAttribute("StatusBurning", true)
    _VFX_BurningStatus(char)

    -- HP drain loop — simple attribute signal; CombatService applies it on Heartbeat
    -- We use "BurningExpiry" so PostureService can check if Burning is still active
    char:SetAttribute("BurningExpiry", tick() + BURNING_DURATION)
    char:SetAttribute("BurningHPPerSecond", BURNING_HP_TICK)

    -- Auto-clear Burning status on expiry
    task.delay(BURNING_DURATION, function()
        if char and char.Parent then
            local expiry = char:GetAttribute("BurningExpiry") :: number?
            if expiry and tick() >= expiry then
                char:SetAttribute("StatusBurning", nil)
                char:SetAttribute("BurningExpiry", nil)
                char:SetAttribute("BurningHPPerSecond", nil)
                -- TALENT HOOK STUB: Heat Transfer — spread 1 stack to adjacent enemies here
            end
        end
    end)

    print(("[Ignite] %s ← %d Heat stack(s) (+%d posture, Burning %.0fs)"):format(
        target.Name, stacks, postureDmg, BURNING_DURATION))
end

-- ─── OnActivate ──────────────────────────────────────────────────────────────

function Ember.OnActivate(player: Player, _targetPos: Vector3?)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local origin  = root.Position
    local forward = root.CFrame.LookVector
    local dest    = origin + forward * DASH_DISTANCE

    -- Read Momentum attribute (set by MovementService)
    local momentum  = (root:GetAttribute("Momentum") :: number?) or 1
    -- TALENT HOOK STUB: Torch — lower threshold to 1.5× here
    local stacks    = if momentum >= MOMENTUM_THRESHOLD then 2 else 1
    -- TALENT HOOK STUB: Ignition Chain — +1 stack if target is airborne

    -- Dash
    task.delay(CAST_TIME, function()
        if not char or not char.Parent then return end
        if not root or not root.Parent then return end

        root.CFrame = CFrame.new(dest, dest + forward)
        _VFX_EmberDash(origin, dest)
        _VFX_IgniteImpact(dest, stacks)

        -- Find targets at landing zone
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { char }

        local hits = Workspace:GetPartBoundsInRadius(dest, HIT_RADIUS, overlapParams)
        local struck: {[Player]: boolean} = {}

        for _, hit in hits do
            local model = hit:FindFirstAncestorOfClass("Model")
            if not model then continue end
            for _, target in Players:GetPlayers() do
                if target == player then continue end
                if struck[target] then continue end
                if target.Character == model then
                    struck[target] = true
                    _applyHeatStack(target, model, stacks, player.Name)
                end
            end
        end

        print(("[Ignite] %s dashed — %d stack(s) (Momentum ×%.1f)"):format(
            player.Name, stacks, momentum))
    end)
end

-- ─── ClientActivate ──────────────────────────────────────────────────────────

function Ember.ClientActivate(targetPosition: Vector3?)
    local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
    local remote = np:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({ AbilityId = Ember.Id, TargetPosition = targetPosition })
    end
end

return Ember
