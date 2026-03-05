--!strict
--[[
    Class: Ash
    Description: ASH — Misdirection, patience, and information advantage.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Ash excels at controlling what opponents think is
                 happening. Best kit for mind games, escapes, and delayed payoffs.
    Issue: #149 — refactor Aspect system to full moveset
    Dependencies: NetworkProvider (lazy)

    Move list:
        [1] AshenStep    (Offensive)  — Dash + decoy afterimage / blind flash
        [2] CinderBurst  (Offensive)  — Point-blank cone / posture stripper
        [3] Fade         (Defensive)  — Reactive escape / damage reduction
        [4] Trace        (UtilityProc)— Marking / information advantage
        [5] GreyVeil     (SelfBuff)   — Offensive amplifier / concealment
]]

local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy-load NetworkProvider — only used server-side inside OnActivate calls
local function _getNetworkProvider()
    return require(ReplicatedStorage.Shared.network.NetworkProvider)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 1 — ASHEN STEP  (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════

local ASHEN_STEP_DASH_DISTANCE  : number = 12   -- studs forward
local ASHEN_STEP_CAST_TIME      : number = 0.15 -- seconds before dash lands
local ASHEN_STEP_POSTURE_DAMAGE : number = 15   -- on-arrival posture
local ASHEN_STEP_POSTURE_RADIUS : number = 5    -- studs around landing
local ASHEN_STEP_AFTERIMAGE_LIFE: number = 4    -- seconds afterimage persists
local ASHEN_STEP_BLIND_DURATION : number = 0.3  -- seconds of BlindFlash

-- VFX STUB — animator: forward ash-smoke particle trail along dash path (0.15s)
local function _VFX_AshenStep_DashTrail(_player: Player, _origin: Vector3, _destination: Vector3) end
-- VFX STUB — animator: ash-particle silhouette materialise at afterimage origin
local function _VFX_AshenStep_AfterimageSpawn(_origin: Vector3) end
-- VFX STUB — animator: ash-particle burst dissolve on afterimage expiry/destruction
local function _VFX_AshenStep_AfterimageDissolve(_part: Part) end
-- VFX STUB — animator: white-out ScreenGui / post-process effect (BLIND_DURATION s)
local function _VFX_AshenStep_BlindFlash(_attacker: Player) end

local function _spawnAfterimage(origin: Vector3, ownerPlayer: Player)
    local part = Instance.new("Part")
    part.Name         = "AshenStepAfterimage"
    part.Transparency = 0.6
    part.BrickColor   = BrickColor.new("Light stone grey")
    part.Material     = Enum.Material.Neon
    part.CFrame       = CFrame.new(origin)
    part.Size         = Vector3.new(2, 5, 1)
    part.Anchored     = true
    part.CanCollide   = false
    part.CastShadow   = false
    part.Parent       = Workspace

    _VFX_AshenStep_AfterimageSpawn(origin)

    local struck = false
    part.Touched:Connect(function(hit: Instance)
        if struck then return end
        local model = hit:FindFirstAncestorOfClass("Model")
        if not model then return end
        local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then return end
        for _, player in game:GetService("Players"):GetPlayers() do
            if player == ownerPlayer then continue end
            if player.Character == model then
                struck = true
                _VFX_AshenStep_BlindFlash(player)
                local ok, np = pcall(_getNetworkProvider)
                if ok and np then
                    -- TALENT HOOK: Hollow Echo — if attacker is Staggered, blindSecs doubles
                    local blindSecs = ASHEN_STEP_BLIND_DURATION
                    pcall(function()
                        np:FireClient(player, "BlindFlash", { Duration = blindSecs })
                    end)
                end
                break
            end
        end
    end)

    task.delay(ASHEN_STEP_AFTERIMAGE_LIFE, function()
        if part and part.Parent then
            _VFX_AshenStep_AfterimageDissolve(part)
            task.wait(0.15)
            part:Destroy()
        end
    end)
end

local function _ashenStep_applyArrivalPosture(caster: Player, landingPos: Vector3)
    for _, target in game:GetService("Players"):GetPlayers() do
        if target == caster then continue end
        local char = target.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then continue end
        if (root.Position - landingPos).Magnitude > ASHEN_STEP_POSTURE_RADIUS then continue end
        char:SetAttribute("IncomingPostureDamage",
            (char:GetAttribute("IncomingPostureDamage") or 0) + ASHEN_STEP_POSTURE_DAMAGE)
        char:SetAttribute("IncomingPostureDamageSource", caster.Name .. "_AshenStep")
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 2 — CINDER BURST  (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  Instant, point-blank cone (6 studs, 30°). 35 posture damage. Applies
--  Exposed (+20% posture received for 3s). Negligible HP damage.
--  No cast time — true punish / melee-cancel tool.

local CINDER_BURST_RANGE          : number = 6
local CINDER_BURST_POSTURE_DAMAGE : number = 35
local CINDER_BURST_EXPOSED_DUR    : number = 3

-- VFX STUB — animator: tight forward cone of compressed ash particles, 0.1s burst
local function _VFX_CinderBurst(_caster: Player, _origin: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 3 — FADE  (Defensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.1s cast. 1.5s window of 80% reduced posture / 50% reduced HP damage.
--  Partial transparency (visible — not full invisibility). Attacking cancels it.
--  On expiry/cancel: small Slow (4 studs, 1s) to nearby targets.

local FADE_DURATION        : number = 1.5
local FADE_EXIT_SLOW_RADIUS: number = 4
local FADE_EXIT_SLOW_DUR   : number = 1

-- VFX STUB — animator: semi-transparent ash-veil overlay on caster model for duration
local function _VFX_Fade_Enter(_caster: Player) end
-- VFX STUB — animator: ash exhale burst, small radial particle cloud on exit
local function _VFX_Fade_Exit(_pos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 4 — TRACE  (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.2s cast. Short ash tendril (10 studs), tracks to nearest target.
--  On hit: Ash Trace mark for 10s — 8-stud wallhack through terrain.
--  Mark invisible to target. 5 posture damage on hit. Lowest mana cost in kit.

local TRACE_RANGE       : number = 10
local TRACE_POSTURE_DMG : number = 5
local TRACE_MARK_DUR    : number = 10
local TRACE_WALLHACK_R  : number = 8

-- VFX STUB — animator: thin ash-smoke tendril projectile, tracking motion
local function _VFX_Trace_Tendril(_origin: Vector3, _target: Vector3) end
-- VFX STUB — animator: subtle ash-ring glow on marked target (visible to caster only)
local function _VFX_Trace_Mark(_targetPos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 5 — GREY VEIL  (SelfBuff)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.3s cast. 5s window: no visible dash trail, dampened ability telegraphs,
--  +25% posture damage output. On window end: Dampened (Momentum reset, 2s)
--  to all targets within 5 studs. Longest cooldown in kit (18s).

local GREY_VEIL_DURATION       : number = 5
local GREY_VEIL_POSTURE_BONUS  : number = 0.25  -- +25%
local GREY_VEIL_EXIT_RADIUS    : number = 5
local GREY_VEIL_DAMPENED_DUR   : number = 2

-- VFX STUB — animator: subtle dark-grey overlay / reduced particle visibility during veil
local function _VFX_GreyVeil_Enter(_caster: Player) end
-- VFX STUB — animator: ash burst ring expanding outward from caster on veil end
local function _VFX_GreyVeil_Exit(_pos: Vector3, _radius: number) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVESET MODULE
-- ═════════════════════════════════════════════════════════════════════════════

local Ash = {
    AspectId    = "Ash",
    DisplayName = "Ash",
    Moves = {} :: any,
}

-- ── Move 1 ───────────────────────────────────────────────────────────────────
Ash.Moves[1] = {
    Id          = "AshenStep",
    Name        = "Ashen Step",
    AspectId    = "Ash",
    Slot        = 1,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "Dash 12 studs forward, leaving a decoy afterimage at the origin. "
                .. "Arrival deals 15 posture in a 5-stud radius. Afterimage persists 4s; "
                .. "anyone who strikes it receives a 0.3s blind flash.",

    CastTime         = ASHEN_STEP_CAST_TIME,
    ManaCost         = 20,
    Cooldown         = 5,
    Range            = ASHEN_STEP_DASH_DISTANCE,
    PostureDamage    = ASHEN_STEP_POSTURE_DAMAGE,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id             = "HollowEcho",
            Name           = "Hollow Echo",
            InteractsWith  = "Stagger",
            Description    = "If the afterimage is hit while the attacker is Staggered, "
                           .. "the blind flash duration doubles to 0.6s. Chains Stagger "
                           .. "into extended vulnerability.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Stagger state hook
        },
        {
            Id             = "MomentumTrace",
            Name           = "Momentum Trace",
            InteractsWith  = "Momentum",
            Description    = "If Ashen Step is cast at ≥2× Momentum, the afterimage mimics "
                           .. "your last sprint direction for 1 second, creating a false "
                           .. "movement vector before freezing. Harder to identify as a decoy.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Momentum attribute check at cast time
        },
        {
            Id             = "HauntingStep",
            Name           = "Haunting Step",
            InteractsWith  = "Airborne",
            Description    = "If cast while airborne, the afterimage spawns at your air "
                           .. "position and falls slowly instead of freezing — a falling decoy "
                           .. "that tracks toward the ground. Disrupts targeting in aerial engagements.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires airborne state detection
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_AshenStep_DashTrail(caster, root.Position, root.Position + root.CFrame.LookVector * ASHEN_STEP_DASH_DISTANCE)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin      = root.Position
        local forward     = root.CFrame.LookVector
        local destination = origin + forward * ASHEN_STEP_DASH_DISTANCE

        task.spawn(_spawnAfterimage, origin, player)
        -- TALENT HOOK STUB: MomentumTrace — check Momentum attribute, mimic sprint dir
        -- TALENT HOOK STUB: HauntingStep  — if airborne, afterimage spawns at air pos

        task.delay(ASHEN_STEP_CAST_TIME, function()
            if not char or not char.Parent then return end
            if not root or not root.Parent then return end
            root.CFrame = CFrame.new(destination, destination + forward)
            _VFX_AshenStep_DashTrail(player, origin, destination)
            _ashenStep_applyArrivalPosture(player, destination)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then
            remote:FireServer({ AbilityId = "AshenStep", TargetPosition = targetPosition })
        end
    end,
}

-- ── Move 2 ───────────────────────────────────────────────────────────────────
Ash.Moves[2] = {
    Id          = "CinderBurst",
    Name        = "Cinder Burst",
    AspectId    = "Ash",
    Slot        = 2,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "Release a tight cone of compressed ash (6 studs, 30° arc) instantly. "
                .. "35 posture damage. Applies Exposed: target takes +20% posture damage "
                .. "from all sources for 3s. No HP damage. Instant cast — true punish tool.",

    CastTime         = 0,   -- instant
    ManaCost         = 20,
    Cooldown         = 7,
    Range            = CINDER_BURST_RANGE,
    PostureDamage    = CINDER_BURST_POSTURE_DAMAGE,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Attacking"},

    Talents = {
        {
            Id             = "ChokingVeil",
            Name           = "Choking Veil",
            InteractsWith  = "Slow",
            Description    = "If Cinder Burst connects from behind (120° rear arc), also "
                           .. "applies Slow for 2s. Rewards flanking over direct confrontation.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires facing/angle check at hit time
        },
        {
            Id             = "AshLung",
            Name           = "Ash Lung",
            InteractsWith  = "Breath",
            Description    = "Targets hit by Cinder Burst have Breath regen rate halved for 3s. "
                           .. "Disrupts movement economy of Silhouette and high-mobility builds.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Breath regen modifier on target
        },
        {
            Id             = "Smothered",
            Name           = "Smothered",
            InteractsWith  = "Exposed + Break",
            Description    = "If you execute a Break on an Exposed target, the Break deals "
                           .. "+15 additional HP damage. Cinder Burst → posture pressure → "
                           .. "Break is now a genuine combo chain.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Break event + Exposed status check
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_CinderBurst(caster, root.Position)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin  = root.Position
        local forward = root.CFrame.LookVector

        local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)
        pcall(function()
            local PostureService = require(game:GetService("ServerScriptService").Server.services.PostureService)
            
            HitboxService.CreateHitbox({
                Shape = "Sphere",
                Owner = player,
                Position = origin + forward * (CINDER_BURST_RANGE/2),
                Size = Vector3.new(CINDER_BURST_RANGE, CINDER_BURST_RANGE, CINDER_BURST_RANGE),
                Damage = CINDER_BURST_POSTURE_DAMAGE,
                LifeTime = 0.5,
                CanHitTwice = false,
                OnHit = function(target: any)
                    local targetModel = nil
                    if typeof(target) == "Instance" and target:IsA("Player") then
                        targetModel = target.Character
                        PostureService.DrainPosture(target, CINDER_BURST_POSTURE_DAMAGE, "Aspect")
                    elseif type(target) == "string" then
                        -- Dummy
                        local DummyService = require(game:GetService("ServerScriptService").Server.services.DummyService)
                        DummyService.ApplyDamage(target, 0, origin)
                        targetModel = workspace:FindFirstChild("Dummy_" .. target)
                    end
                    
                    if targetModel then
                        local tRoot = targetModel:FindFirstChild("HumanoidRootPart")
                        if tRoot then
                            local toTarget = tRoot.Position - origin
                            if toTarget.Magnitude > 0.01 and forward:Dot(toTarget.Unit) >= 0.866 then
                                targetModel:SetAttribute("StatusExposed", true)
                                targetModel:SetAttribute("ExposedExpiry", tick() + CINDER_BURST_EXPOSED_DUR)
                                task.delay(CINDER_BURST_EXPOSED_DUR, function()
                                    if targetModel and targetModel.Parent then
                                        targetModel:SetAttribute("StatusExposed", nil)
                                        targetModel:SetAttribute("ExposedExpiry", nil)
                                    end
                                end)
                            end
                        end
                    end
                end
            })
        end)
        _VFX_CinderBurst(player, origin)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then
            remote:FireServer({ AbilityId = "CinderBurst", TargetPosition = targetPosition })
        end
    end,
}

-- ── Move 3 ───────────────────────────────────────────────────────────────────
Ash.Moves[3] = {
    Id          = "Fade",
    Name        = "Fade",
    AspectId    = "Ash",
    Slot        = 3,
    Type        = "Expression",
    MoveType    = "Defensive",
    Description = "Phase into partial transparency for 1.5s. Incoming posture damage -80%, "
                .. "HP damage -50%. Attacking cancels early. On expiry/cancel: Slow (4 studs, 1s) "
                .. "to all nearby targets. Longest cooldown in kit.",

    CastTime         = 0.1,
    ManaCost         = 25,
    Cooldown         = 12,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping"},

    Talents = {
        {
            Id             = "AshenShroud",
            Name           = "Ashen Shroud",
            InteractsWith  = "Airborne",
            Description    = "If Fade is activated while airborne, you also gain a brief upward "
                           .. "drift (small vertical float) that breaks lock-on targeting for "
                           .. "the duration. Aerial escape tool.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires airborne detection + lock-on break network event
        },
        {
            Id             = "Exhale",
            Name           = "Exhale",
            InteractsWith  = "Slow + Posture",
            Description    = "Fade's exit Slow also applies Exposed (2s) in addition to Slow. "
                           .. "The window after Fade becomes a setup window, not just a breather.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Exposed application on exit
        },
        {
            Id             = "BreathReserve",
            Name           = "Breath Reserve",
            InteractsWith  = "Breath",
            Description    = "Activating Fade restores 20 Breath, regardless of current pool. "
                           .. "Incentivizes Fade as a mid-movement tool rather than panic button.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Breath attribute write on activation
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_Fade_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- Signal CombatService that Fade is active (it reads this for damage reduction)
        char:SetAttribute("StatusFade", true)
        char:SetAttribute("FadeExpiry", tick() + FADE_DURATION)
        _VFX_Fade_Enter(player)

        -- TALENT HOOK STUB: AshenShroud — if airborne, add upward float + break lock-on
        -- TALENT HOOK STUB: BreathReserve — restore 20 Breath immediately

        task.delay(FADE_DURATION, function()
            if not char or not char.Parent then return end
            -- Clear fade if not already cancelled
            if char:GetAttribute("StatusFade") then
                char:SetAttribute("StatusFade", nil)
                char:SetAttribute("FadeExpiry", nil)

                -- Exit Slow to nearby targets
                local myPos = root.Position
                for _, target in game:GetService("Players"):GetPlayers() do
                    if target == player then continue end
                    local tChar = target.Character
                    if not tChar then continue end
                    local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not tRoot then continue end
                    if (tRoot.Position - myPos).Magnitude > FADE_EXIT_SLOW_RADIUS then continue end
                    tChar:SetAttribute("StatusSlow", true)
                    tChar:SetAttribute("SlowExpiry", tick() + FADE_EXIT_SLOW_DUR)
                    -- TALENT HOOK STUB: Exhale — also apply Exposed (2s) here
                    task.delay(FADE_EXIT_SLOW_DUR, function()
                        if tChar and tChar.Parent then
                            tChar:SetAttribute("StatusSlow", nil)
                            tChar:SetAttribute("SlowExpiry", nil)
                        end
                    end)
                end
                _VFX_Fade_Exit(myPos)
            end
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then
            remote:FireServer({ AbilityId = "Fade", TargetPosition = targetPosition })
        end
    end,
}

-- ── Move 4 ───────────────────────────────────────────────────────────────────
Ash.Moves[4] = {
    Id          = "Trace",
    Name        = "Trace",
    AspectId    = "Ash",
    Slot        = 4,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Fire a short ash tendril (10 studs, auto-tracks nearest target). On hit: "
                .. "Ash Trace mark for 10s — 8-stud wallhack shows marked target through terrain. "
                .. "Mark invisible to target. 5 posture on hit. Lowest mana cost in kit.",

    CastTime         = 0.2,
    ManaCost         = 15,
    Cooldown         = 8,
    Range            = TRACE_RANGE,
    PostureDamage    = TRACE_POSTURE_DMG,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id             = "ResonanceTrace",
            Name           = "Resonance Trace",
            InteractsWith  = "Living Resonance",
            Description    = "If the marked target has an active Living Resonance streak, Trace "
                           .. "also reveals their approximate HP percentage via HUD text for the "
                           .. "duration. Directly counters the 'tanky streak' playstyle.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires streak data network read
        },
        {
            Id             = "BurningMark",
            Name           = "Burning Mark",
            InteractsWith  = "Exposed",
            Description    = "If the marked target is already Exposed (from Cinder Burst), the "
                           .. "Trace mark also increases all damage they take by 5% for the "
                           .. "remaining Exposed duration. Stacking proc tool.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Exposed check + damage multiplier attribute
        },
        {
            Id             = "ShadowTendril",
            Name           = "Shadow Tendril",
            InteractsWith  = "Airborne",
            Description    = "Trace can be cast vertically upward at a 45° angle to mark "
                           .. "airborne targets. Standard horizontal cast cannot track airborne targets.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires cast angle toggle UI
        },
    },

    VFX_Function = function(_caster: Player, _targetPos: Vector3?)
        -- VFX STUB — animator: ash tendril thin-line projectile tracking nearest target
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- Find nearest target within range
        local bestTarget: Player? = nil
        local bestDist = TRACE_RANGE + 1
        local myPos = root.Position

        for _, target in game:GetService("Players"):GetPlayers() do
            if target == player then continue end
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not tRoot then continue end
            local d = (tRoot.Position - myPos).Magnitude
            if d < bestDist then
                bestDist = d
                bestTarget = target
            end
        end

        if not bestTarget then return end

        local tChar = bestTarget.Character
        if not tChar then return end
        local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not tRoot then return end

        -- Apply posture hit
        tChar:SetAttribute("IncomingPostureDamage",
            (tChar:GetAttribute("IncomingPostureDamage") or 0) + TRACE_POSTURE_DMG)
        tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_Trace")

        -- Apply Ash Trace mark (wallhack signal to client via attribute; client reads it)
        tChar:SetAttribute("AshTraceOwner", player.Name)
        tChar:SetAttribute("AshTraceExpiry", tick() + TRACE_MARK_DUR)

        -- TALENT HOOK STUB: ResonanceTrace — if marked has Resonance streak, fire HP% to client HUD
        -- TALENT HOOK STUB: BurningMark — if Exposed, apply +5% damage multiplier
        -- TALENT HOOK STUB: ShadowTendril — vertical cast angle for airborne targets

        -- Auto-clear mark
        task.delay(TRACE_MARK_DUR, function()
            if tChar and tChar.Parent then
                if (tChar:GetAttribute("AshTraceOwner") :: string?) == player.Name then
                    tChar:SetAttribute("AshTraceOwner", nil)
                    tChar:SetAttribute("AshTraceExpiry", nil)
                end
            end
        end)

        _VFX_Trace_Tendril(myPos, tRoot.Position)
        _VFX_Trace_Mark(tRoot.Position)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then
            remote:FireServer({ AbilityId = "Trace", TargetPosition = targetPosition })
        end
    end,
}

-- ── Move 5 ───────────────────────────────────────────────────────────────────
Ash.Moves[5] = {
    Id          = "GreyVeil",
    Name        = "Grey Veil",
    AspectId    = "Ash",
    Slot        = 5,
    Type        = "Expression",
    MoveType    = "SelfBuff",
    Description = "Wrap yourself in ash for 5s. Dash leaves no visible trail, ability "
                .. "start-up telegraphs are dampened, posture damage output +25%. "
                .. "On expiry: Dampened (Momentum reset + 2s lock) to all targets within 5 studs. "
                .. "Longest cooldown in kit (18s).",

    CastTime         = 0.3,
    ManaCost         = 30,
    Cooldown         = 18,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running"},

    Talents = {
        {
            Id             = "VeilStriker",
            Name           = "Veil Striker",
            InteractsWith  = "Momentum",
            Description    = "If you deal a Break during Grey Veil, the cooldown is immediately "
                           .. "reduced by 8 seconds. Rewards closing fights quickly inside the window.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Break event hook + CDR
        },
        {
            Id             = "SilencedApproach",
            Name           = "Silenced Approach",
            InteractsWith  = "Silenced",
            Description    = "When Grey Veil activates, any target within 5 studs is immediately "
                           .. "Silenced for 1 second. Close-range opener that takes away a "
                           .. "response tool immediately.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Silenced status application on cast
        },
        {
            Id             = "LingeringVeil",
            Name           = "Lingering Veil",
            InteractsWith  = "Slow",
            Description    = "The exit burst now also applies Slow (2s) in addition to Dampened. "
                           .. "Combined Slow + Dampened + momentum lock makes escape from Ash very difficult.",
            IsUnlocked     = false,
            OnActivate     = nil, -- STUB — requires Slow application in exit burst
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_GreyVeil_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- Activate veil state — CombatService/MovementService read these attributes
        char:SetAttribute("StatusGreyVeil", true)
        char:SetAttribute("GreyVeilExpiry", tick() + GREY_VEIL_DURATION)
        char:SetAttribute("GreyVeilPostureBonus", GREY_VEIL_POSTURE_BONUS)

        _VFX_GreyVeil_Enter(player)

        -- TALENT HOOK STUB: SilencedApproach — Silence nearby targets on activation

        task.delay(GREY_VEIL_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusGreyVeil", nil)
            char:SetAttribute("GreyVeilExpiry", nil)
            char:SetAttribute("GreyVeilPostureBonus", nil)

            local myPos = root.Position

            -- Exit burst: apply Dampened to nearby targets
            for _, target in game:GetService("Players"):GetPlayers() do
                if target == player then continue end
                local tChar = target.Character
                if not tChar then continue end
                local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if not tRoot then continue end
                if (tRoot.Position - myPos).Magnitude > GREY_VEIL_EXIT_RADIUS then continue end
                tChar:SetAttribute("StatusDampened", true)
                tChar:SetAttribute("DampenedExpiry", tick() + GREY_VEIL_DAMPENED_DUR)
                -- TALENT HOOK STUB: LingeringVeil — also apply Slow here
                task.delay(GREY_VEIL_DAMPENED_DUR, function()
                    if tChar and tChar.Parent then
                        tChar:SetAttribute("StatusDampened", nil)
                        tChar:SetAttribute("DampenedExpiry", nil)
                    end
                end)
            end

            _VFX_GreyVeil_Exit(myPos, GREY_VEIL_EXIT_RADIUS)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then
            remote:FireServer({ AbilityId = "GreyVeil", TargetPosition = targetPosition })
        end
    end,
}


-- ─── VFX stubs ───────────────────────────────────────────────────────────────

-- VFX STUB: emit forward-motion particle trail along dash path
local function _VFX_DashTrail(_player: Player, _origin: Vector3, _destination: Vector3)
    -- VFX STUB — animator: ash-smoke particle trail, 0.15s duration
end

-- VFX STUB: materialise the afterimage decoy
local function _VFX_AfterimageSpawn(_origin: Vector3)
    -- VFX STUB — animator: ash-particle silhouette materialise, looping idle shimmer
end

-- VFX STUB: dissolve the afterimage (natural expiry or destruction)
local function _VFX_AfterimageDissolve(_part: Part)
    -- VFX STUB — animator: ash-particle burst dissolve, 0.15s
end

-- VFX STUB: blind flash to the attacker who struck the image
local function _VFX_BlindFlash(_attacker: Player)
    -- VFX STUB — animator: white-out ScreenGui / post-process effect, BLIND_DURATION seconds
end

-- ─── Afterimage helper ────────────────────────────────────────────────────────

--[[
    _spawnAfterimage(origin, ownerPlayer)
    Creates a serverside BasePart acting as the afterimage decoy.
    Any player who touches it (via Touched) receives a BlindFlash.
    Part is destroyed after AFTERIMAGE_LIFE seconds.
]]
local function _spawnAfterimage(origin: Vector3, _ownerPlayer: Player)
    local part = Instance.new("Part")
    part.Name       = "AshenStepAfterimage"
    part.Transparency = 0.6
    part.BrickColor   = BrickColor.new("Light stone grey")
    part.Material     = Enum.Material.Neon
    part.CFrame       = CFrame.new(origin)
    part.Size         = Vector3.new(2, 5, 1)   -- rough humanoid silhouette
    part.Anchored     = true
    part.CanCollide   = false
    part.CastShadow   = false
    part.Parent       = Workspace

    _VFX_AfterimageSpawn(origin)

    local struck = false

    -- Detect when an enemy player hits the afterimage
    part.Touched:Connect(function(hit: Instance)
        if struck then return end  -- only flash once per afterimage
        -- Identify the humanoid/player that struck the image
        local model = hit:FindFirstAncestorOfClass("Model")
        if not model then return end
        local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then return end

        -- Find the player that owns this character
        for _, player in game:GetService("Players"):GetPlayers() do
            if player.Character == model then
                struck = true
                _VFX_BlindFlash(player)
                -- Signal blind flash to the client
                local ok, np = pcall(_getNetworkProvider)
                if ok and np then
                    -- TALENT HOOK: Hollow Echo — if attacker is Staggered, double duration
                    -- TALENT HOOK STUB: check character attribute "Staggered" here when talent system exists
                    local blindSecs = BLIND_DURATION
                    pcall(function()
                        np:FireClient(player, "BlindFlash", { Duration = blindSecs })
                    end)
                end
                print(("[AshenStep] BlindFlash → %s for %.1fs"):format(player.Name, BLIND_DURATION))
                break
            end
        end
    end)

    -- Auto-destroy after lifetime
    task.delay(AFTERIMAGE_LIFE, function()
        if part and part.Parent then
            _VFX_AfterimageDissolve(part)
            task.wait(0.15)
            part:Destroy()
        end
    end)

    return part
end

-- ─── Posture damage helper ────────────────────────────────────────────────────

--[[
    _applyArrivalPostureDamage(caster, landingPos)
    Finds any player character within POSTURE_RADIUS of landingPos and applies
    posture damage via the "PostureDamageSource" attribute (read by PostureService
    on the next heartbeat).  Avoids damaging the caster themselves.
]]
local function _applyArrivalPostureDamage(caster: Player, landingPos: Vector3)
    for _, target in game:GetService("Players"):GetPlayers() do
        if target == caster then continue end
        local char = target.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then continue end
        if (root.Position - landingPos).Magnitude > POSTURE_RADIUS then continue end

        -- Signal PostureService/CombatService via character attribute
        -- PostureService reads "IncomingPostureDamage" and applies it on Heartbeat
        char:SetAttribute("IncomingPostureDamage",
            (char:GetAttribute("IncomingPostureDamage") or 0) + POSTURE_DAMAGE)
        char:SetAttribute("IncomingPostureDamageSource", caster.Name)
        print(("[AshenStep] Posture dmg %d → %s"):format(POSTURE_DAMAGE, target.Name))
    end
end

-- ─── OnActivate ──────────────────────────────────────────────────────────────

--[[
    Called server-side by AbilitySystem.HandleExpressionAbility.
    @param player        The caster.
    @param _targetPos    Direction hint from client (unused; dash is always forward).
]]
function Ash.OnActivate(player: Player, _targetPos: Vector3?)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local origin      = root.Position
    local forward     = root.CFrame.LookVector
    local destination = origin + forward * DASH_DISTANCE

    -- Spawn afterimage at origin before moving (decoy stays where we were)
    task.spawn(_spawnAfterimage, origin, player)

    -- TALENT HOOK STUB: Momentum Trace — if Momentum ≥ 2×, afterimage mimics last sprint dir
    -- TALENT HOOK STUB: Haunting Step  — if airborne, spawn afterimage in air

    -- Brief cast delay (0.15s) then teleport caster to destination
    task.delay(CAST_TIME, function()
        if not char or not char.Parent then return end
        if not root or not root.Parent then return end

        -- Simple position move — animator will tween the visual
        root.CFrame = CFrame.new(destination, destination + forward)
        _VFX_DashTrail(player, origin, destination)

        -- Apply posture damage to any nearby player at landing
        _applyArrivalPostureDamage(player, destination)

        print(("[AshenStep] %s dashed %.1f studs"):format(player.Name, DASH_DISTANCE))
    end)
end

-- ─── ClientActivate  ─────────────────────────────────────────────────────────

--[[
    Called client-side to request the cast; sends AbilityCastRequest to server.
]]
function Ash.ClientActivate(targetPosition: Vector3?)
    local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
    local remote = np:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({ AbilityId = Ash.Id, TargetPosition = targetPosition })
    end
end

return Ash
