--!strict
--[[
    Class: Tide
    Description: TIDE — Resource denial, terrain weaponization, sustainable pressure.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Only Aspect that directly manipulates opponent Breath, Posture
                 recovery, and positioning. Best for long fights and punishing
                 movement-heavy builds.
    Issue: #149 — refactor Aspect system to full moveset
    Dependencies: none (server-only via OnActivate)

    Move list:
        [1] Current    (Offensive)   — Ranged surge knockback / terrain weapon
        [2] Undertow   (UtilityProc) — Pull / setup (counters retreat)
        [3] Swell      (Defensive)   — Reactive posture shell / self-sustain
        [4] FloodMark  (UtilityProc) — Area denial / Saturated setter
        [5] Pressure   (SelfBuff)    — Parry-immunity window / Saturated amplifier
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 1 — CURRENT  (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════

local CURRENT_RANGE         : number = 15   -- studs forward
local CURRENT_RADIUS        : number = 5    -- hit sphere at tip
local CURRENT_KNOCKBACK     : number = 8    -- studs of pushback
local CURRENT_POSTURE_DMG   : number = 25
local CURRENT_WALL_HP_DMG   : number = 20   -- bonus if target hits terrain
local CURRENT_GROUNDED_DUR  : number = 1.5
local CURRENT_WET_ZONE_SIZE : number = 4    -- studs wide (talent stub)

-- VFX STUB — animator: water-ribbon projectile 15 studs forward
local function _VFX_Current_Surge(_origin: Vector3, _direction: Vector3) end
-- VFX STUB — animator: foam-splash radial burst at tip on hit
local function _VFX_Current_Hit(_hitPos: Vector3) end
-- VFX STUB — animator: heavy water-crash wave on terrain impact
local function _VFX_Current_TerrainImpact(_pos: Vector3) end

local function _applyGrounded(char: Model, duration: number)
    char:SetAttribute("StatusGrounded", true)
    task.delay(duration, function()
        if char and char.Parent then
            char:SetAttribute("StatusGrounded", nil)
        end
    end)
end

local function _applyKnockbackAndMonitor(caster: Player, target: Player, direction: Vector3)
    local tChar = target.Character
    if not tChar then return end
    local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not tRoot then return end

    tRoot.AssemblyLinearVelocity = direction.Unit * CURRENT_KNOCKBACK * 20

    local detected = false
    local conn: RBXScriptConnection
    conn = tRoot.Touched:Connect(function(hit: Instance)
        if detected then return end
        if hit:IsDescendantOf(tChar) then return end
        if not hit:IsA("BasePart") then return end
        local bp = hit :: BasePart
        if not bp.CanCollide then return end
        detected = true
        conn:Disconnect()
        tChar:SetAttribute("IncomingHPDamage",
            (tChar:GetAttribute("IncomingHPDamage") or 0) + CURRENT_WALL_HP_DMG)
        tChar:SetAttribute("IncomingHPDamageSource", caster.Name .. "_Current_Wall")
        _applyGrounded(tChar, CURRENT_GROUNDED_DUR)
        _VFX_Current_TerrainImpact(tRoot.Position)
    end)
    task.delay(1, function()
        if not detected and conn then conn:Disconnect() end
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 2 — UNDERTOW  (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  Pull target toward you over 8 studs. Arrival Slow (1.5s). Light HP (10pts).
--  If retreating when hit: pull doubles to 16 studs, Slow extends to 3s.
--  Requires target within 8 studs. Does not work on airborne targets.

local UNDERTOW_BASE_RANGE : number = 8
local UNDERTOW_HP_DMG     : number = 10
local UNDERTOW_SLOW_BASE  : number = 1.5
local UNDERTOW_SLOW_BONUS : number = 3.0

-- VFX STUB — animator: pulling water stream toward caster origin
local function _VFX_Undertow(_casterPos: Vector3, _targetPos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 3 — SWELL  (Defensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.4s cast. 2s or 3-hit water shell: -60% incoming posture. On release: restore 20%
--  max Posture. Minor pushback (3 studs) to targets within 2 studs on release.

local SWELL_DURATION        : number = 2
local SWELL_MAX_HITS        : number = 3
local SWELL_POSTURE_RESTORE : number = 0.20  -- % of max Posture
local SWELL_PUSHBACK_DIST   : number = 3
local SWELL_PUSHBACK_RADIUS : number = 2

-- VFX STUB — animator: water droplet shell materialises around caster, cracks and shatters on release
local function _VFX_Swell_Enter(_caster: Player) end
local function _VFX_Swell_Release(_pos: Vector3, _radius: number) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 4 — FLOOD MARK  (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.25s cast. Place wet zone at target location (12 stud range, 8 stud radius).
--  Zone persists 8s. Targets inside: Saturated immediately + Posture regen -50%.
--  Zone itself deals no damage.

local FLOOD_MARK_RANGE      : number = 12
local FLOOD_MARK_RADIUS     : number = 8
local FLOOD_MARK_DURATION   : number = 8

-- VFX STUB — animator: water pool materialising on ground at target location, shimmering for duration
local function _VFX_FloodMark_Create(_pos: Vector3, _radius: number) end
local function _VFX_FloodMark_Expire(_pos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 5 — PRESSURE  (SelfBuff)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.2s cast. 6s flowing state: melee cannot be parried, all Tide abilities
--  apply Saturated on hit. On expiry: restore 15 Mana.

local PRESSURE_DURATION     : number = 6
local PRESSURE_MANA_RESTORE : number = 15

-- VFX STUB — animator: water constantly flowing around caster legs / arms during state
local function _VFX_Pressure_Enter(_caster: Player) end
local function _VFX_Pressure_Exit(_pos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVESET MODULE
-- ═════════════════════════════════════════════════════════════════════════════

local Tide = {
    AspectId    = "Tide",
    DisplayName = "Tide",
    Moves = {} :: any,
}

-- ── Move 1 ───────────────────────────────────────────────────────────────────
Tide.Moves[1] = {
    Id          = "Current",
    Name        = "Current",
    AspectId    = "Tide",
    Slot        = 1,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "Project a water surge 15 studs forward. Hit: 25 posture, knocked back 8 studs. "
                .. "If target hits terrain: +20 HP damage and Grounded (1.5s). "
                .. "Does not hit airborne targets.",

    CastTime         = 0.3,
    ManaCost         = 20,
    Cooldown         = 7,
    Range            = CURRENT_RANGE,
    PostureDamage    = CURRENT_POSTURE_DMG,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "Riptide",
            Name          = "Riptide",
            InteractsWith = "Airborne",
            Description   = "Targets who dodge Current while airborne are instead knocked downward "
                          .. "(slammed to ground, brief stagger). Anti-air counter for Gale/jump builds.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne dodge detection
        },
        {
            Id            = "SaturatingWave",
            Name          = "Saturating Wave",
            InteractsWith = "Saturated",
            Description   = "Current leaves a 4-stud wide wet zone along its path for 5s. "
                          .. "Targets moving through it gain Saturated (+25% Ember damage).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires zone creation along surge path
        },
        {
            Id            = "DrowningShore",
            Name          = "Drowning Shore",
            InteractsWith = "Breath",
            Description   = "Targets at ≤25% Breath when hit by Current are also Dampened (2s). "
                          .. "Punishes Breath-exhausted opponents who are overcommitted.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Breath attribute check at hit time
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_Current_Surge(root.Position, root.CFrame.LookVector)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin    = root.Position
        local direction = root.CFrame.LookVector
        local tipPos    = origin + direction * CURRENT_RANGE

        -- Use HitboxService for physical collision detection
        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        pcall(function()
            local PostureService = require(game:GetService("ServerScriptService").Server.services.PostureService)
            
            HitboxService.CreateHitbox({
                Shape = "Sphere",
                Owner = player,
                Position = tipPos,
                Size = Vector3.new(CURRENT_RADIUS, CURRENT_RADIUS, CURRENT_RADIUS),
                Damage = CURRENT_POSTURE_DMG,
                LifeTime = 0.5,
                CanHitTwice = false,
                OnHit = function(target: any)
                    local tPlayer = typeof(target) == "Instance" and target:IsA("Player") and target or nil
                    if tPlayer then
                        PostureService.DrainPosture(tPlayer, CURRENT_POSTURE_DMG, "Aspect")
                        _applyKnockbackAndMonitor(player, tPlayer, direction)
                    elseif type(target) == "string" then
                        -- Dummy dummyId
                        local DummyService = require(game:GetService("ServerScriptService").Server.services.DummyService)
                        DummyService.ApplyDamage(target, 0, root.Position)
                    end
                end
            })
        end)
        
        _VFX_Current_Surge(origin, direction)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Current", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 2 ───────────────────────────────────────────────────────────────────
Tide.Moves[2] = {
    Id          = "Undertow",
    Name        = "Undertow",
    AspectId    = "Tide",
    Slot        = 2,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Pull target toward you over 8 studs. Arrival Slow (1.5s). 10 HP damage. "
                .. "If retreating: pull doubles to 16 studs, Slow extends to 3s. "
                .. "Does not work on airborne targets.",

    CastTime         = 0.2,
    ManaCost         = 20,
    Cooldown         = 8,
    Range            = UNDERTOW_BASE_RANGE,
    PostureDamage    = nil,
    BaseDamage       = UNDERTOW_HP_DMG,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "FloodSense",
            Name          = "Flood Sense",
            InteractsWith = "Saturated",
            Description   = "Saturated targets hit by Undertow take double the Slow duration "
                          .. "(3s → 6s). Saturated + Undertow removes mobility for a full engagement window.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Saturated status check at hit time
        },
        {
            Id            = "TidalLock",
            Name          = "Tidal Lock",
            InteractsWith = "Posture",
            Description   = "After Undertow lands, your next attack within 2s cannot be blocked — "
                          .. "target is off-balance. The anti-block window rewards immediate follow-up.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires temporary block-immunity attribute on caster
        },
        {
            Id            = "SurfaceTension",
            Name          = "Surface Tension",
            InteractsWith = "Grounded",
            Description   = "If the pulled target passes over a wet zone during pull, "
                          .. "they gain Grounded instead of Slow. Requires Current setup.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires wet zone detection during pull path
        },
    },

    VFX_Function = function(_caster: Player, _targetPos: Vector3?)
        -- VFX STUB — animator: pulling water stream from target to caster over 0.3s
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local myPos = root.Position

        -- Find nearest target within range
        local bestTarget: Player? = nil
        local bestDist = UNDERTOW_BASE_RANGE + 1
        for _, target in Players:GetPlayers() do
            if target == player then continue end
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not tRoot then continue end
            local d = (tRoot.Position - myPos).Magnitude
            if d < bestDist then bestDist = d; bestTarget = target end
        end

        if not bestTarget then return end
        local tChar = bestTarget.Character
        if not tChar then return end
        local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not tRoot then return end

        -- Detect if retreating (velocity.dot(towardMe) < 0 means moving away)
        local towardMe = (myPos - tRoot.Position)
        local vel = tRoot.AssemblyLinearVelocity
        local isRetreating = vel.Magnitude > 0.5 and vel.Unit:Dot(towardMe.Unit) < -0.3
        local pullDist = if isRetreating then UNDERTOW_BASE_RANGE * 2 else UNDERTOW_BASE_RANGE
        local slowDur  = if isRetreating then UNDERTOW_SLOW_BONUS else UNDERTOW_SLOW_BASE

        -- Pull: set velocity toward caster
        local pullDir = (myPos - tRoot.Position).Unit
        tRoot.AssemblyLinearVelocity = pullDir * pullDist * 12  -- scaled

        -- HP damage
        tChar:SetAttribute("IncomingHPDamage",
            (tChar:GetAttribute("IncomingHPDamage") or 0) + UNDERTOW_HP_DMG)
        tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_Undertow")

        -- Arrival Slow
        task.delay(0.4, function()
            if not tChar or not tChar.Parent then return end
            tChar:SetAttribute("StatusSlow", true)
            tChar:SetAttribute("SlowExpiry", tick() + slowDur)
            -- TALENT HOOK STUB: FloodSense — if Saturated, double slow duration
            -- TALENT HOOK STUB: TidalLock — grant caster block-bypass for 2s
            -- TALENT HOOK STUB: SurfaceTension — if wet zone crossed, Grounded instead
            task.delay(slowDur, function()
                if tChar and tChar.Parent then
                    tChar:SetAttribute("StatusSlow", nil)
                    tChar:SetAttribute("SlowExpiry", nil)
                end
            end)
        end)

        _VFX_Undertow(myPos, tRoot.Position)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Undertow", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 3 ───────────────────────────────────────────────────────────────────
Tide.Moves[3] = {
    Id          = "Swell",
    Name        = "Swell",
    AspectId    = "Tide",
    Slot        = 3,
    Type        = "Expression",
    MoveType    = "Defensive",
    Description = "Encase in water shell for 2s or 3 hits. Incoming posture -60%. "
                .. "On release: restore 20% max Posture. Minor 3-stud pushback "
                .. "within 2 studs of target. Longest cast time in kit (0.4s).",

    CastTime         = 0.4,
    ManaCost         = 25,
    Cooldown         = 14,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "TidalSurge",
            Name          = "Tidal Surge",
            InteractsWith = "Momentum",
            Description   = "If Swell releases at ≥2× Momentum, pushback range increases from "
                          .. "3 to 7 studs and applies Slow (1s). Punishes aggressive Momentum builds.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum check at release time
        },
        {
            Id            = "DeepBreath",
            Name          = "Deep Breath",
            InteractsWith = "Breath",
            Description   = "Swell's 2s window also fully restores your Breath pool. "
                          .. "The defensive window is also a breath reset — enables movement burst immediately.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Breath attribute full restore on activation
        },
        {
            Id            = "ReflectCurrent",
            Name          = "Reflect Current",
            InteractsWith = "Slow (incoming)",
            Description   = "If you are Slowed when Swell activates, the Slow is transferred to "
                          .. "all targets within 4 studs on activation. Counter-tool against Ash/Tide.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Slow status check + transfer on cast
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_Swell_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local hitsAbsorbed = 0
        char:SetAttribute("StatusSwell", true)
        char:SetAttribute("SwellHitsRemaining", SWELL_MAX_HITS)
        char:SetAttribute("SwellExpiry", tick() + SWELL_DURATION)
        _VFX_Swell_Enter(player)

        -- TALENT HOOK STUB: DeepBreath — restore Breath immediately
        -- TALENT HOOK STUB: ReflectCurrent — if Slowed, transfer Slow to nearby targets

        local function releaseSwell()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusSwell", nil)
            char:SetAttribute("SwellHitsRemaining", nil)
            char:SetAttribute("SwellExpiry", nil)

            -- Restore 20% max Posture (PostureService reads attribute)
            char:SetAttribute("PostureRestore", SWELL_POSTURE_RESTORE)

            -- Pushback nearby targets
            local myPos = root.Position
            for _, target in Players:GetPlayers() do
                if target == player then continue end
                local tChar = target.Character
                if not tChar then continue end
                local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if not tRoot then continue end
                if (tRoot.Position - myPos).Magnitude > SWELL_PUSHBACK_RADIUS then continue end
                local pushDir = (tRoot.Position - myPos).Unit
                tRoot.AssemblyLinearVelocity = pushDir * SWELL_PUSHBACK_DIST * 15
                -- TALENT HOOK STUB: TidalSurge — if Momentum ≥2×, extend to 7 studs + Slow
            end
            _VFX_Swell_Release(myPos, SWELL_PUSHBACK_RADIUS)
        end

        task.delay(SWELL_DURATION, releaseSwell)
        -- Note: hit absorption tracking (up to 3 hits) is handled by CombatService/PostureService
        -- reading the SwellHitsRemaining attribute and decrementing it on each hit.
        -- When it reaches 0, they should also call the release (attribute set to nil triggers this).
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Swell", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 4 ───────────────────────────────────────────────────────────────────
Tide.Moves[4] = {
    Id          = "FloodMark",
    Name        = "Flood Mark",
    AspectId    = "Tide",
    Slot        = 4,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Place a wet zone at target location (12 stud range, 8 stud radius) for 8s. "
                .. "Targets inside: immediately Saturated, Posture regen -50% while inside. "
                .. "Saturated targets take +25% damage from Ember abilities.",

    CastTime         = 0.25,
    ManaCost         = 15,
    Cooldown         = 9,
    Range            = FLOOD_MARK_RANGE,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "StagnantPool",
            Name          = "Stagnant Pool",
            InteractsWith = "Grounded",
            Description   = "Targets who take a hit (any source) while standing in a Flood Mark "
                          .. "zone gain Grounded for 1s. Any hit inside the zone triggers Grounded.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires zone-hit event in CombatService
        },
        {
            Id            = "RisingTide",
            Name          = "Rising Tide",
            InteractsWith = "Posture",
            Description   = "While standing in your own Flood Mark zone, your Posture regen rate "
                          .. "is doubled instead of halved. Positional advantage.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires zone ownership tracking in PostureService
        },
        {
            Id            = "PhantomDepth",
            Name          = "Phantom Depth",
            InteractsWith = "Airborne",
            Description   = "Flood Mark zones pull airborne targets 2 studs downward when cast "
                          .. "directly below them, applying Grounded on landing. Limited anti-air.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne detection at zone cast time
        },
    },

    VFX_Function = function(_caster: Player, targetPos: Vector3?)
        if not targetPos then return end
        _VFX_FloodMark_Create(targetPos, FLOOD_MARK_RADIUS)
    end,

    OnActivate = function(player: Player, targetPos: Vector3?)
        if not targetPos then return end

        -- Create a Part to represent the zone (detected by zone-overlap checks)
        local zonePart = Instance.new("Part")
        zonePart.Name        = "TideFloodMarkZone"
        zonePart.Anchored    = true
        zonePart.CanCollide  = false
        zonePart.Transparency = 1
        zonePart.Size        = Vector3.new(FLOOD_MARK_RADIUS * 2, 0.5, FLOOD_MARK_RADIUS * 2)
        zonePart.CFrame      = CFrame.new(targetPos)
        zonePart:SetAttribute("ZoneOwner", player.Name)
        zonePart:SetAttribute("ZoneType", "TideFloodMark")
        zonePart:SetAttribute("ZoneExpiry", tick() + FLOOD_MARK_DURATION)
        zonePart.Parent      = Workspace

        _VFX_FloodMark_Create(targetPos, FLOOD_MARK_RADIUS)

        -- Apply Saturated to any player already in zone
        for _, target in Players:GetPlayers() do
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not tRoot then continue end
            if (tRoot.Position - targetPos).Magnitude <= FLOOD_MARK_RADIUS then
                tChar:SetAttribute("StatusSaturated", true)
                -- TALENT HOOK STUB: PhantomDepth — if airborne, pull 2 studs down + Grounded
            end
        end

        -- TALENT HOOK STUBS: StagnantPool — wire to CombatService hit events
        --                    RisingTide   — wire to PostureService regen calculation

        task.delay(FLOOD_MARK_DURATION, function()
            if zonePart and zonePart.Parent then
                _VFX_FloodMark_Expire(targetPos)
                zonePart:Destroy()
            end
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "FloodMark", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 5 ───────────────────────────────────────────────────────────────────
Tide.Moves[5] = {
    Id          = "Pressure",
    Name        = "Pressure",
    AspectId    = "Tide",
    Slot        = 5,
    Type        = "Expression",
    MoveType    = "SelfBuff",
    Description = "Enter flowing state for 6s. Melee cannot be parried. All Tide abilities "
                .. "apply Saturated on hit regardless. On expiry: restore 15 Mana.",

    CastTime         = 0.2,
    ManaCost         = 30,
    Cooldown         = 16,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id            = "CurrentState",
            Name          = "Current State",
            InteractsWith = "Momentum",
            Description   = "Activating Pressure grants 1 Momentum stack instantly. "
                          .. "The buff and a Momentum start fire together.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Momentum attribute increment
        },
        {
            Id            = "FlowingForm",
            Name          = "Flowing Form",
            InteractsWith = "Slow (self)",
            Description   = "Tide abilities cast during Pressure cannot trigger Slow on yourself. "
                          .. "Removes one vulnerability during your offensive window.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires self-Slow immunity flag during state
        },
        {
            Id            = "UndertowPressure",
            Name          = "Undertow Pressure",
            InteractsWith = "Slow + Saturated",
            Description   = "Undertow cast during Pressure applies Saturated and Slow simultaneously. "
                          .. "Combo compressor — normally requires two casts.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Pressure state check in Undertow OnActivate
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_Pressure_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- Signal that Pressure is active; CombatService reads for parry-immunity
        char:SetAttribute("StatusPressure", true)
        char:SetAttribute("PressureExpiry", tick() + PRESSURE_DURATION)

        _VFX_Pressure_Enter(player)
        -- TALENT HOOK STUB: CurrentState — increment Momentum attribute by 1
        -- TALENT HOOK STUB: FlowingForm  — set self-Slow immunity flag

        task.delay(PRESSURE_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusPressure", nil)
            char:SetAttribute("PressureExpiry", nil)

            -- Restore mana via profile attribute (DataService reads on next tick)
            char:SetAttribute("ManaRestore", PRESSURE_MANA_RESTORE)

            _VFX_Pressure_Exit(root.Position)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Pressure", TargetPosition = targetPosition }) end
    end,
}

local function _VFX_SurgeProjectile(_origin: Vector3, _direction: Vector3)
    -- VFX STUB — animator: water-ribbon projectile travelling in direction over 0.15s
end

local function _VFX_SurgeHit(_hitPos: Vector3)
    -- VFX STUB — animator: foam-splash radial particle burst at hitPos
end

local function _VFX_TerrainImpact(_targetPos: Vector3)
    -- VFX STUB — animator: heavy water-crash landing wave when target hits terrain
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

--[[
    _applyGrounded(char, duration)
    Sets the Grounded status attribute on the character so MovementService can
    block jumps/vaults/wallruns.  Auto-clears after duration.
]]
local function _applyGrounded(char: Model, duration: number)
    char:SetAttribute("StatusGrounded", true)
    task.delay(duration, function()
        if char and char.Parent then
            char:SetAttribute("StatusGrounded", nil)
        end
    end)
end

--[[
    _monitorTerrainCollision(target, char, root, duration)
    Watches for the target's root to touch a non-player Part within `duration`
    seconds after knockback.  On first collision applies TERRAIN_HP_BONUS damage
    and Grounded status.
]]
local function _monitorTerrainCollision(target: Player, char: Model, root: BasePart, duration: number)
    local detected = false
    local conn: RBXScriptConnection
    conn = root.Touched:Connect(function(hit: Instance)
        if detected then return end
        -- Ignore touches from the player's own body parts
        if hit:IsDescendantOf(char) then return end
        -- Only react to solid Workspace physical parts (not sensors, triggers, etc.)
        if not hit:IsA("BasePart") then return end
        local bp = hit :: BasePart
        if bp.CanCollide == false then return end

        detected = true
        conn:Disconnect()

        -- HP damage via character attribute (read by CombatService/PostureService)
        char:SetAttribute("IncomingHPDamage",
            (char:GetAttribute("IncomingHPDamage") or 0) + TERRAIN_HP_BONUS)
        char:SetAttribute("IncomingHPDamageSource", "Current_TerrainImpact")

        _applyGrounded(char, GROUNDED_DURATION)
        _VFX_TerrainImpact(root.Position)
        print(("[Current] Terrain impact — %s grounded %.1fs +%dHP"):format(
            target.Name, GROUNDED_DURATION, TERRAIN_HP_BONUS))
    end)

    -- Auto-disconnect if no terrain collision occurs within the window
    task.delay(duration, function()
        if not detected and conn then
            conn:Disconnect()
        end
    end)
end

--[[
    _applyKnockback(target, casterPos)
    Pushes the target's HumanoidRootPart away from casterPos by KNOCKBACK_DIST.
    Uses VectorForce for a physics-friendly impulse on the next frame.
]]
local function _applyKnockback(target: Player, casterPos: Vector3)
    local char = target.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local dir = (root.Position - casterPos).Unit
    root.AssemblyLinearVelocity = dir * KNOCKBACK_DIST * 20  -- impulse scaling

    -- TALENT HOOK STUB: Riptide — double knockback if target is airborne
    -- (check root.AssemblyLinearVelocity.Y > 0 or StatusAirborne attribute)

    -- Monitor terrain hit for bonus
    _monitorTerrainCollision(target, char, root, 1)
end

-- ─── OnActivate ──────────────────────────────────────────────────────────────

function Tide.OnActivate(player: Player, targetPos: Vector3?)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    -- Direction: prefer explicit targetPos, fall back to look vector
    local casterPos = root.Position
    local direction: Vector3
    if targetPos then
        direction = (targetPos - casterPos).Unit
    else
        direction = root.CFrame.LookVector
    end

    local surgeEnd = casterPos + direction * SURGE_RANGE

    _VFX_SurgeProjectile(casterPos, direction)

    task.delay(CAST_TIME, function()
        if not char or not char.Parent then return end

        -- Sphere overlap at surge tip — find any player root within SURGE_RADIUS
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { char }  -- exclude caster

        local hits = Workspace:GetPartBoundsInRadius(surgeEnd, SURGE_RADIUS, overlapParams)

        local struck: {[Player]: boolean} = {}
        for _, hit in hits do
            local model = hit:FindFirstAncestorOfClass("Model")
            if not model then continue end
            for _, target in Players:GetPlayers() do
                if target == player then continue end
                if struck[target] then continue end
                if target.Character == model then
                    struck[target] = true

                    -- Posture damage
                    model:SetAttribute("IncomingPostureDamage",
                        (model:GetAttribute("IncomingPostureDamage") or 0) + POSTURE_DAMAGE)
                    model:SetAttribute("IncomingPostureDamageSource", player.Name)

                    -- TALENT HOOK STUB: Saturating Wave — apply Saturated here
                    -- TALENT HOOK STUB: Drowning Shore  — halve Breath regen here

                    -- Knockback
                    _applyKnockback(target, casterPos)

                    _VFX_SurgeHit(surgeEnd)
                    print(("[Current] Hit %s — %d posture, knockback"):format(target.Name, POSTURE_DAMAGE))
                end
            end
        end
    end)
end

-- ─── ClientActivate ──────────────────────────────────────────────────────────

function Tide.ClientActivate(targetPosition: Vector3?)
    local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
    local remote = np:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({ AbilityId = Tide.Id, TargetPosition = targetPosition })
    end
end

return Tide
