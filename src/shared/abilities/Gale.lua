--!strict
--[[
    Class: Gale
    Description: GALE — Aerial control, vertical pressure, zone disruption.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Owns the vertical axis. Gale rewards landing airborne
                 targets and punishes flat-ground opponents with knockback into air.
    Issue: #149 — refactor Aspect system to full moveset
    Dependencies: none (server-only via OnActivate)

    Move list:
        [1] WindStrike  (Offensive)   — Dash launch, both parties Weightless
        [2] Crosswind   (UtilityProc) — Lateral push, aerial bonus
        [3] Windwall    (Defensive)   — Ranged barrier + auto-reposition
        [4] Updraft     (SelfBuff)    — Vertical launch, next ability +damage
        [5] Shear       (Offensive)   — 180° arc sweep, doubled vs airborne
]]

local Players = game:GetService("Players")

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 1 — WINDSTRIKE (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════
-- Descriptions:
--   Dash 12 studs at target. On hit: launch both caster and target (Weightless 0.5s).
--   Airborne bonus: if caster OR target is airborne at cast, +50% posture damage.
--   2× Momentum: taller launch + 1s window after landing where next ability does +20%.

local WINDSTRIKE_DASH_DIST      : number = 12
local WINDSTRIKE_POSTURE_BASE   : number = 20
local WINDSTRIKE_HIT_RADIUS     : number = 5
local WINDSTRIKE_LAUNCH_DUR     : number = 0.5
local WINDSTRIKE_AERIAL_MULT    : number = 1.5

-- VFX STUB — animator: wind trail on dash, double upward burst at contact
local function _VFX_WindStrike_Dash(_origin: Vector3, _dest: Vector3) end
local function _VFX_WindStrike_Impact(_pos: Vector3) end
-- VFX STUB — animator: Weightless shimmer on both targets
local function _VFX_Weightless(_char: Model) end

local function _isAirborne(char: Model): boolean
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    return hum.FloorMaterial == Enum.Material.Air
end

local function _applyWeightless(char: Model, duration: number)
    char:SetAttribute("StatusWeightless", true)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.JumpHeight = 0   -- lock grounded jump during float
    end
    _VFX_Weightless(char)
    task.delay(duration, function()
        if not char or not char.Parent then return end
        char:SetAttribute("StatusWeightless", nil)
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then h.JumpHeight = 7.2 end  -- restore default
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 2 — CROSSWIND (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.1s cast. Push target 4 studs laterally (perpendicular to caster facing).
--  12 posture damage. If target is airborne: skip posture, deal 15 HP + camera spin 1s.
--  If target hits a wall: Grounded 1s.

local CROSSWIND_PUSH_DIST       : number = 4
local CROSSWIND_POSTURE_DMG     : number = 12
local CROSSWIND_AERIAL_HP_DMG   : number = 15
local CROSSWIND_HIT_RADIUS      : number = 8
local CROSSWIND_GROUNDED_DUR    : number = 1

-- VFX STUB — animator: horizontal wind shear, dust kick at push origin
local function _VFX_Crosswind(_origin: Vector3, _direction: Vector3) end
-- VFX STUB — animator: brief spiral distortion on target UI (camera spin)
local function _VFX_CameraSpinDebuff(_target: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 3 — WINDWALL (Defensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.2s cast. 1.5s barrier / 2-hit capacity. Deflects ranged Aspect abilities.
--  Melee hits absorbed: 50% posture reduction. On expiry: auto-reposition 3 studs backward.

local WINDWALL_DURATION     : number = 1.5
local WINDWALL_HIT_CAPACITY : number = 2
local WINDWALL_MELEE_MULT   : number = 0.5
local WINDWALL_REPOSITION   : number = 3

-- VFX STUB — animator: translucent wind barrier in front of caster
local function _VFX_Windwall_Enter(_caster: Player) end
local function _VFX_Windwall_Exit(_caster: Player) end
-- VFX STUB — animator: deflected projectile ricochets visual
local function _VFX_Deflect(_pos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 4 — UPDRAFT (SelfBuff)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.1s cast. Launch self 8-12 studs vertically. Next ability within 3s deals +25%.
--  Resets air-redirect cooldown. Breath suspended 0.5s at apex (inhale window).

local UPDRAFT_LAUNCH_HEIGHT : number = 10  -- middle of 8-12 range
local UPDRAFT_BUFF_DURATION : number = 3
local UPDRAFT_DMG_BONUS     : number = 0.25

-- VFX STUB — animator: column of wind lifting caster, feathers/leaves swirling at apex
local function _VFX_Updraft_Launch(_pos: Vector3) end
-- VFX STUB — animator: pulsing wind aura while buff is active
local function _VFX_UpdraftBuff_Enter(_caster: Player) end
local function _VFX_UpdraftBuff_Exit(_caster: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 5 — SHEAR (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.3s cast. 180° arc sweep 8 studs. 15 HP + 30 posture to all targets in arc.
--  Airborne targets: 30 HP instead of 15 + Grounded 2s on landing.
--  Cooldown reduced to 8s if cast while caster is airborne (within last 2s via GaleShear talent).

local SHEAR_ARC_DEGREES     : number = 180
local SHEAR_RANGE           : number = 8
local SHEAR_HP_DMG          : number = 15
local SHEAR_POSTURE_DMG     : number = 30
local SHEAR_AERIAL_HP_MULT  : number = 2    -- 30 HP vs airborne
local SHEAR_GROUNDED_DUR    : number = 2

-- VFX STUB — animator: wide side-to-side wind slash arc, leaves/debris in wake
local function _VFX_Shear(_origin: Vector3, _forward: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVESET MODULE
-- ═════════════════════════════════════════════════════════════════════════════

local Gale = {
    AspectId    = "Gale",
    DisplayName = "Gale",
    Moves       = {} :: any,
}

-- ── Move 1 ───────────────────────────────────────────────────────────────────
Gale.Moves[1] = {
    Id          = "WindStrike",
    Name        = "Wind Strike",
    AspectId    = "Gale",
    Slot        = 1,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "Dash 12 studs at target. Both caster and target become Weightless 0.5s. "
                .. "If either is already airborne at cast: +50% posture damage. "
                .. "2× Momentum: taller launch + next ability +20% dmg within 1s of landing.",

    CastTime         = 0.15,
    ManaCost         = 20,
    Cooldown         = 6,
    Range            = WINDSTRIKE_DASH_DIST,
    PostureDamage    = WINDSTRIKE_POSTURE_BASE,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping"},

    Talents = {
        {
            Id            = "Updraft",
            Name          = "Updraft (passive)",
            InteractsWith = "Breath",
            Description   = "WindStrike restores 10 Breath on contact. Ensures the launch "
                          .. "investment doesn't strand you out of sprint resources mid-fight.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Breath restore on hit confirmation
        },
        {
            Id            = "GaleForce",
            Name          = "Gale Force",
            InteractsWith = "Momentum",
            Description   = "At 2× Momentum, launch height is 1.5× taller and the landing "
                          .. "window for +20% next ability extends to 2s. Deepens Momentum investment.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum tier check at cast
        },
        {
            Id            = "TempestDive",
            Name          = "Tempest Dive",
            InteractsWith = "Airborne",
            Description   = "If caster has 5+ stud Y-axis advantage over target at cast, "
                          .. "deal +20 HP direct damage (in addition to posture). Diving bonus.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Y-delta check at cast time
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_WindStrike_Dash(root.Position, root.Position + root.CFrame.LookVector * WINDSTRIKE_DASH_DIST)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin  = root.Position
        local forward = root.CFrame.LookVector
        local dest    = origin + forward * WINDSTRIKE_DASH_DIST
        local casterAirborne = _isAirborne(char)

        task.delay(0.15, function()
            if not char or not char.Parent then return end
            if not root or not root.Parent then return end
            root.CFrame = CFrame.new(dest, dest + forward)
            _VFX_WindStrike_Dash(origin, dest)

            local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
            pcall(function()
                local PostureService = require(game:GetService("ServerScriptService").Server.services.PostureService)
                
                HitboxService.CreateHitbox({
                    Shape = "Sphere",
                    Owner = player,
                    Position = dest,
                    Size = Vector3.new(WINDSTRIKE_HIT_RADIUS, WINDSTRIKE_HIT_RADIUS, WINDSTRIKE_HIT_RADIUS),
                    Damage = 0,
                    LifeTime = 0.5,
                    CanHitTwice = false,
                    OnHit = function(hitTarget: any)
                        local tChar
                        local tPlayer
                        if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                            tPlayer = hitTarget
                            tChar = hitTarget.Character
                        elseif type(hitTarget) == "string" then
                            local DummyService = require(game:GetService("ServerScriptService").Server.services.DummyService)
                            tChar = DummyService:GetDummyModel(hitTarget)
                        end
                        if not tChar then return end
                        
                        local targetAirborne = _isAirborne(tChar)
                        local aerialBonus = (casterAirborne or targetAirborne) and WINDSTRIKE_AERIAL_MULT or 1
                        local postureDmg = math.floor(WINDSTRIKE_POSTURE_BASE * aerialBonus)

                        if tPlayer then
                            PostureService.DrainPosture(tPlayer, postureDmg, "Aspect")
                        elseif tChar:FindFirstChildWhichIsA("Humanoid") then
                            -- Dummy posture damage
                            local dummyPosture = tChar:GetAttribute("Posture")
                            if dummyPosture then
                                tChar:SetAttribute("Posture", math.max(0, dummyPosture - postureDmg))
                            else
                                tChar:SetAttribute("IncomingPostureDamage", (tChar:GetAttribute("IncomingPostureDamage") or 0) + postureDmg)
                                tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_WindStrike")
                            end
                        end
                        
                        _VFX_WindStrike_Impact(dest)

                        -- Launch both caster and target (Weightless)
                        _applyWeightless(tChar, WINDSTRIKE_LAUNCH_DUR)
                        _applyWeightless(char,  WINDSTRIKE_LAUNCH_DUR)

                        -- Apply upward velocity impulse
                        local tRoot = tChar:FindFirstChild("HumanoidRootPart")
                        if tRoot then
                            tRoot.AssemblyLinearVelocity = Vector3.new(0, 55, 0)
                        end
                        if root then
                            root.AssemblyLinearVelocity = Vector3.new(0, 35, 0)
                        end
                    end
                })
            end)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "WindStrike", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 2 ───────────────────────────────────────────────────────────────────
Gale.Moves[2] = {
    Id          = "Crosswind",
    Name        = "Crosswind",
    AspectId    = "Gale",
    Slot        = 2,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Push nearest target 4 studs laterally (perpendicular to caster's facing). "
                .. "12 posture damage. If target is airborne: no posture, 15 HP + camera spin 1s. "
                .. "If target hits a wall: Grounded 1s.",

    CastTime         = 0.1,
    ManaCost         = 15,
    Cooldown         = 7,
    Range            = CROSSWIND_HIT_RADIUS,
    PostureDamage    = CROSSWIND_POSTURE_DMG,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping", "Attacking"},

    Talents = {
        {
            Id            = "SlipDraft",
            Name          = "Slip Draft",
            InteractsWith = "Wall",
            Description   = "If target hits a wall from Crosswind, deal 30 HP direct in addition "
                          .. "to Grounded. Wall collision becomes a punish, not just a reset.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires wall-collision detection on pushed target
        },
        {
            Id            = "AirPocket",
            Name          = "Air Pocket",
            InteractsWith = "Air Redirect",
            Description   = "Crosswind resets your air redirect cooldown on hit. "
                          .. "Combined with Updraft for prolonged aerial chains.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires air redirect CD attribute reset
        },
        {
            Id            = "GustWarning",
            Name          = "Gust Warning",
            InteractsWith = "Momentum",
            Description   = "If target has exactly 1× Momentum at time of hit, apply Dampened "
                          .. "(Momentum reset) instead of only posture damage.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum attribute check on target
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        -- Push direction: perpendicular to facing (right side)
        local right = root.CFrame.RightVector
        _VFX_Crosswind(root.Position, right)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin    = root.Position
        local rightDir  = root.CFrame.RightVector  -- lateral axis

        _VFX_Crosswind(origin, rightDir)

        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        pcall(function()
            HitboxService.CreateHitbox({
                Shape = "Circle",
                Owner = player,
                Position = origin,
                Radius = CROSSWIND_HIT_RADIUS,
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
                    local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not tRoot then return end

                    local airborne = _isAirborne(tChar)

                    if airborne then
                        -- Aerial version: HP + camera spin, no posture
                        tChar:SetAttribute("IncomingHPDamage",
                            (tChar:GetAttribute("IncomingHPDamage") or 0) + CROSSWIND_AERIAL_HP_DMG)
                        tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_CrosswindAerial")
                        -- Camera spin is client-side debuff signal
                        tChar:SetAttribute("StatusCameraSpun", true)
                        tChar:SetAttribute("CameraSpinExpiry", tick() + 1)
                        if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                            _VFX_CameraSpinDebuff(hitTarget)
                        end
                        task.delay(1, function()
                            if tChar and tChar.Parent then
                                tChar:SetAttribute("StatusCameraSpun", nil)
                                tChar:SetAttribute("CameraSpinExpiry", nil)
                            end
                        end)
                    else
                        tChar:SetAttribute("IncomingPostureDamage",
                            (tChar:GetAttribute("IncomingPostureDamage") or 0) + CROSSWIND_POSTURE_DMG)
                        tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_Crosswind")
                    end

                    -- Lateral impulse (push right relative to caster)
                    tRoot.AssemblyLinearVelocity = rightDir * (CROSSWIND_PUSH_DIST * 20)

                    -- TALENT HOOK STUB: GustWarning — if Momentum == 1, apply Dampened
                    -- TALENT HOOK STUB: AirPocket   — reset air redirect CD on hit
                    -- Wall hit detection (STUB — requires onCollision event or raycast polling)
                    -- TALENT HOOK STUB: SlipDraft   — if wall hit, +30 HP + Grounded
                    task.delay(0.05, function()
                        if not tChar or not tChar.Parent then return end
                        if not tRoot or not tRoot.Parent then return end
                        -- Simple wall-proximity check: if velocity dropped sharply, apply Grounded
                        if tRoot.AssemblyLinearVelocity.Magnitude < 2 then
                            tChar:SetAttribute("StatusGrounded", true)
                            tChar:SetAttribute("GroundedExpiry", tick() + CROSSWIND_GROUNDED_DUR)
                            task.delay(CROSSWIND_GROUNDED_DUR, function()
                                if tChar and tChar.Parent then
                                    tChar:SetAttribute("StatusGrounded", nil)
                                    tChar:SetAttribute("GroundedExpiry", nil)
                                end
                            end)
                        end
                    end)
                end
            })
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Crosswind", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 3 ───────────────────────────────────────────────────────────────────
Gale.Moves[3] = {
    Id          = "Windwall",
    Name        = "Windwall",
    AspectId    = "Gale",
    Slot        = 3,
    Type        = "Expression",
    MoveType    = "Defensive",
    Description = "1.5s directional barrier, 2-hit capacity. Deflects ranged Aspect abilities. "
                .. "Absorbed melee: 50% posture reduction for attacker. "
                .. "On expiry or broken: auto-reposition 3 studs backward.",

    CastTime         = 0.2,
    ManaCost         = 25,
    Cooldown         = 13,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Blocking"},

    Talents = {
        {
            Id            = "WindWhip",
            Name          = "Wind Whip",
            InteractsWith = "Reposition",
            Description   = "Toggle: instead of repositioning backward on expiry, launch upward "
                          .. "3 studs (Updraft mini-launch). Converts escape to aerial setup.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires reposition toggle detection
        },
        {
            Id            = "Redirect",
            Name          = "Redirect",
            InteractsWith = "Projectile",
            Description   = "Deflected ranged Aspect abilities create a 2-stud Slow zone at "
                          .. "deflection point for 2s. Turns blocked attacks into area denial.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires projectile deflect hook + Slow zone creation
        },
        {
            Id            = "EyeOfTheStorm",
            Name          = "Eye of the Storm",
            InteractsWith = "Momentum",
            Description   = "While Windwall is active and absorbing, you gain 1 Momentum stack. "
                          .. "Being defended successfully rewards aggression investment.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum grant on block during active state
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_Windwall_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        char:SetAttribute("StatusWindwall", true)
        char:SetAttribute("WindwallExpiry", tick() + WINDWALL_DURATION)
        char:SetAttribute("WindwallHitsLeft", WINDWALL_HIT_CAPACITY)
        _VFX_Windwall_Enter(player)

        -- TALENT HOOK STUB: EyeOfTheStorm — grant 1 Momentum while active

        local function _expire()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusWindwall", nil)
            char:SetAttribute("WindwallExpiry", nil)
            char:SetAttribute("WindwallHitsLeft", nil)

            -- Auto-reposition backward
            -- TALENT HOOK STUB: WindWhip — if toggle set, launch up instead of back
            if root and root.Parent then
                local back = -root.CFrame.LookVector
                root.CFrame = CFrame.new(root.Position + back * WINDWALL_REPOSITION)
            end

            _VFX_Windwall_Exit(player)
        end

        task.delay(WINDWALL_DURATION, _expire)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Windwall", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 4 ───────────────────────────────────────────────────────────────────
Gale.Moves[4] = {
    Id          = "Updraft",
    Name        = "Updraft",
    AspectId    = "Gale",
    Slot        = 4,
    Type        = "Expression",
    MoveType    = "SelfBuff",
    Description = "Launch self 8-12 studs vertically. Next ability within 3s deals +25% damage. "
                .. "Resets air redirect cooldown. Breath suspended 0.5s at apex.",

    CastTime         = 0.1,
    ManaCost         = 20,
    Cooldown         = 10,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping"},

    Talents = {
        {
            Id            = "StormsEye",
            Name          = "Storm's Eye",
            InteractsWith = "Airborne",
            Description   = "Aerial abilities cast while the Updraft damage buff is active deal "
                          .. "+15 Posture (flat bonus) in addition to the +25% multiplier.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires aerial state check at next ability cast
        },
        {
            Id            = "BreathOfWind",
            Name          = "Breath of Wind",
            InteractsWith = "Breath",
            Description   = "At apex of Updraft launch (0.5s Breath suspend), fully restore Breath "
                          .. "to max. Converts altitude into instant stamina recovery.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Breath full restore at apex timing
        },
        {
            Id            = "GaleDive",
            Name          = "Gale Dive",
            InteractsWith = "Momentum",
            Description   = "On landing after Updraft, if contact is made within 2s of launch, "
                          .. "gain +1 Momentum stack. Downward dive is rewarded.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires landing detection within time window
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_Updraft_Launch(root.Position)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- Vertical launch
        root.AssemblyLinearVelocity = Vector3.new(0, UPDRAFT_LAUNCH_HEIGHT * 5, 0)
        _VFX_Updraft_Launch(root.Position)

        -- Damage buff on next ability
        char:SetAttribute("StatusUpdraftBuff", true)
        char:SetAttribute("UpdraftBuffExpiry", tick() + UPDRAFT_BUFF_DURATION)
        char:SetAttribute("UpdraftDamageBonus", UPDRAFT_DMG_BONUS)
        _VFX_UpdraftBuff_Enter(player)

        -- Breath suspend at apex (~0.5s after launch peak)
        -- TALENT HOOK STUB: BreathOfWind — full Breath restore at apex
        -- TALENT HOOK STUB: StormsEye    — +15 posture to aerial abilities during buff

        task.delay(UPDRAFT_BUFF_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusUpdraftBuff", nil)
            char:SetAttribute("UpdraftBuffExpiry", nil)
            char:SetAttribute("UpdraftDamageBonus", nil)
            _VFX_UpdraftBuff_Exit(player)
        end)

        -- Reset air redirect CD
        char:SetAttribute("AirRedirectLastUsed", 0)
        -- TALENT HOOK STUB: GaleDive — on landing within 2s, +1 Momentum
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Updraft", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 5 ───────────────────────────────────────────────────────────────────
Gale.Moves[5] = {
    Id          = "Shear",
    Name        = "Shear",
    AspectId    = "Gale",
    Slot        = 5,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "180° arc sweep 8 studs: 15 HP + 30 posture. "
                .. "Airborne targets: 30 HP + Grounded 2s on landing. "
                .. "Cooldown 8s if cast while airborne (down from 14s).",

    CastTime         = 0.3,
    ManaCost         = 30,
    Cooldown         = 14,
    Range            = SHEAR_RANGE,
    PostureDamage    = SHEAR_POSTURE_DMG,
    BaseDamage       = SHEAR_HP_DMG,
    IsAoE            = true,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping", "Attacking"},

    Talents = {
        {
            Id            = "WindCutter",
            Name          = "Wind Cutter",
            InteractsWith = "Momentum",
            Description   = "At 3× Momentum, Shear sweeps 360° instead of 180°. "
                          .. "Maximum Momentum converts the sweep into a full circle of destruction.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum check → arc override at cast
        },
        {
            Id            = "GaleShear",
            Name          = "Gale Shear",
            InteractsWith = "Airborne",
            Description   = "Shear cast while airborne (or within 2s of landing) reduces "
                          .. "cooldown to 8s instead of 14s. Rewards aerial aggression.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne state check → CDR override
        },
        {
            Id            = "Condor",
            Name          = "Condor",
            InteractsWith = "Weightless",
            Description   = "Targets with active Weightless (from WindStrike) hit by Shear "
                          .. "remain Weightless 1.5s longer. Chains air combos.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Weightless attribute check + duration extend
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_Shear(root.Position, root.CFrame.LookVector)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin   = root.Position
        local forward  = root.CFrame.LookVector

        -- Check if caster was airborne (GaleShear talent: CDR on aerial cast)
        local casterAirborne = _isAirborne(char)
        -- TALENT HOOK STUB: GaleShear — if casterAirborne, set cooldown override to 8s
        -- TALENT HOOK STUB: WindCutter — if Momentum == 3, sweep = 360° (arc = math.pi*2)

        -- Arc detection: check if target is within 180° cone in front
        local halfArcRad = math.rad(SHEAR_ARC_DEGREES / 2)
        _VFX_Shear(origin, forward)

        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        pcall(function()
            HitboxService.CreateHitbox({
                Shape = "Cone",
                Owner = player,
                Origin = origin,
                Direction = forward,
                Length = SHEAR_RANGE,
                Angle = 85, -- Wide arc
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

                    local airborne = _isAirborne(tChar)
                    local hpDmg    = airborne and (SHEAR_HP_DMG * SHEAR_AERIAL_HP_MULT) or SHEAR_HP_DMG

                    tChar:SetAttribute("IncomingHPDamage",
                        (tChar:GetAttribute("IncomingHPDamage") or 0) + hpDmg)
                    tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_Shear")

                    tChar:SetAttribute("IncomingPostureDamage",
                        (tChar:GetAttribute("IncomingPostureDamage") or 0) + SHEAR_POSTURE_DMG)
                    tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_ShearPosture")

                    -- Airborne → Grounded on landing
                    if airborne then
                        tChar:SetAttribute("StatusGroundedOnLand", true)
                        tChar:SetAttribute("GroundedOnLandDuration", SHEAR_GROUNDED_DUR)
                        -- TALENT HOOK STUB: Condor — if Weightless, extend Weightless 1.5s
                    end
                end
            })
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Shear", TargetPosition = targetPosition }) end
    end,
}


-- ─── VFX stubs ───────────────────────────────────────────────────────────────

local function _VFX_WindDash(_origin: Vector3, _dest: Vector3)
    -- VFX STUB — animator: wind-ribbon dash trail over CAST_TIME seconds
end

local function _VFX_LaunchBurst(_pos: Vector3, _isAirborne: boolean)
    -- VFX STUB — animator: upward gust column and spiral particles at pos
    --            if isAirborne, intensity should be visibly stronger
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

--[[
    _isAirborne(root) → boolean
    Returns true if the root part is more than AIRBORNE_THRESHOLD studs above
    solid terrain (raycast downward).
]]
local function _isAirborne(root: BasePart): boolean
    local rayResult = Workspace:Raycast(
        root.Position,
        Vector3.new(0, -(AIRBORNE_THRESHOLD + 1), 0),
        RaycastParams.new()
    )
    return rayResult == nil  -- no hit below → airborne
end

--[[
    _launchCharacter(root, velocityY)
    Adds an upward velocity impulse using AssemblyLinearVelocity.
    Preserves existing horizontal velocity so the character continues their
    forward trajectory mid-air (looks intentional rather than snapping).
]]
local function _launchCharacter(root: BasePart, velocityY: number)
    local current = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(current.X, velocityY, current.Z)
end

-- ─── OnActivate ──────────────────────────────────────────────────────────────

function Gale.OnActivate(player: Player, _targetPos: Vector3?)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local origin   = root.Position
    local forward  = root.CFrame.LookVector
    local dest     = origin + forward * DASH_DISTANCE

    -- Determine if cast is airborne BEFORE the dash moves us
    local casterAirborne = _isAirborne(root)
    local postureDmg     = if casterAirborne then POSTURE_DAMAGE_AIR else POSTURE_DAMAGE_GROUND
    local launchVY       = if casterAirborne then LAUNCH_VELOCITY_AIR else LAUNCH_VELOCITY

    task.delay(CAST_TIME, function()
        if not char or not char.Parent then return end
        if not root or not root.Parent then return end

        -- Move caster to destination
        root.CFrame = CFrame.new(dest, dest + forward)
        _VFX_WindDash(origin, dest)

        -- Launch caster upward
        _launchCharacter(root, launchVY)
        _VFX_LaunchBurst(dest, casterAirborne)

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

                    -- Posture damage via attribute
                    model:SetAttribute("IncomingPostureDamage",
                        (model:GetAttribute("IncomingPostureDamage") or 0) + postureDmg)
                    model:SetAttribute("IncomingPostureDamageSource", player.Name .. "_WindStrike")

                    -- Launch target upward
                    local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if targetRoot then
                        _launchCharacter(targetRoot, launchVY)
                        _VFX_LaunchBurst(targetRoot.Position, casterAirborne)

                        -- TALENT HOOK STUB: Updraft — block target Breath regen while airborne
                        -- Set attribute that MovementService checks
                        -- model:SetAttribute("StatusBreathBlocked", true)   -- deferred

                        -- TALENT HOOK STUB: Gale Force — grant 1× Momentum to caster on landing
                    end

                    print(("[WindStrike] %s ← %d posture + launched%s"):format(
                        target.Name, postureDmg, if casterAirborne then " (aerial bonus)" else ""))
                end
            end
        end

        -- TALENT HOOK STUB: Tempest Dive — mark caster for aerial follow-up window
        -- char:SetAttribute("TempestDiveReady", tick() + 3)   -- deferred

        print(("[WindStrike] %s dashed + launched (casterAirborne=%s)"):format(
            player.Name, tostring(casterAirborne)))
    end)
end

-- ─── ClientActivate ──────────────────────────────────────────────────────────

function Gale.ClientActivate(targetPosition: Vector3?)
    local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
    local remote = np:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({ AbilityId = Gale.Id, TargetPosition = targetPosition })
    end
end

return Gale
