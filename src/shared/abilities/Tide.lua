--!strict
--[[
    Class: Tide
    Description: TIDE â€” Resource denial, terrain weaponization, sustainable pressure.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Only Aspect that directly manipulates opponent Breath, Posture
                 recovery, and positioning. Best for long fights and punishing
                 movement-heavy builds.
    Issue: #149 â€” refactor Aspect system to full moveset
    Dependencies: none (server-only via OnActivate)

    Move list:
        [1] Current    (Offensive)   â€” Ranged surge knockback / terrain weapon
        [2] Undertow   (UtilityProc) â€” Pull / setup (counters retreat)
        [3] Swell      (Defensive)   â€” Reactive posture shell / self-sustain
        [4] FloodMark  (UtilityProc) â€” Area denial / Saturated setter
        [5] Pressure   (SelfBuff)    â€” Parry-immunity window / Saturated amplifier
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 1 â€” CURRENT  (Offensive)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local CURRENT_RANGE         : number = 15   -- studs forward
local CURRENT_RADIUS        : number = 5    -- hit sphere at tip
local CURRENT_KNOCKBACK     : number = 8    -- studs of pushback
local CURRENT_POSTURE_DMG   : number = 25
local CURRENT_HP_DMG        : number = 15   -- HP damage on hit (placeholder)
local CURRENT_WALL_HP_DMG   : number = 20   -- bonus if target hits terrain
local CURRENT_GROUNDED_DUR  : number = 1.5
local CURRENT_WET_ZONE_SIZE : number = 4    -- studs wide (talent stub)

-- VFX STUB â€” animator: water-ribbon projectile 15 studs forward
local function _VFX_Current_Surge(_origin: Vector3, _direction: Vector3) end
-- VFX STUB â€” animator: foam-splash radial burst at tip on hit
local function _VFX_Current_Hit(_hitPos: Vector3) end
-- VFX STUB â€” animator: heavy water-crash wave on terrain impact
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

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 2 â€” UNDERTOW  (UtilityProc)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  Pull target toward you over 8 studs. Arrival Slow (1.5s). Light HP (10pts).
--  If retreating when hit: pull doubles to 16 studs, Slow extends to 3s.
--  Requires target within 8 studs. Does not work on airborne targets.

local UNDERTOW_BASE_RANGE : number = 8
local UNDERTOW_HP_DMG     : number = 10
local UNDERTOW_SLOW_BASE  : number = 1.5
local UNDERTOW_SLOW_BONUS : number = 3.0

-- VFX STUB â€” animator: pulling water stream toward caster origin
local function _VFX_Undertow(_casterPos: Vector3, _targetPos: Vector3) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 3 â€” SWELL  (Defensive)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.4s cast. 2s or 3-hit water shell: -60% incoming posture. On release: restore 20%
--  max Posture. Minor pushback (3 studs) to targets within 2 studs on release.

local SWELL_DURATION        : number = 2
local SWELL_MAX_HITS        : number = 3
local SWELL_POSTURE_RESTORE : number = 0.20  -- % of max Posture
local SWELL_PUSHBACK_DIST   : number = 3
local SWELL_PUSHBACK_RADIUS : number = 2

-- VFX STUB â€” animator: water droplet shell materialises around caster, cracks and shatters on release
local function _VFX_Swell_Enter(_caster: Player) end
local function _VFX_Swell_Release(_pos: Vector3, _radius: number) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 4 â€” FLOOD MARK  (UtilityProc)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.25s cast. Place wet zone at target location (12 stud range, 8 stud radius).
--  Zone persists 8s. Targets inside: Saturated immediately + Posture regen -50%.
--  Zone itself deals no damage.

local FLOOD_MARK_RANGE      : number = 12
local FLOOD_MARK_RADIUS     : number = 8
local FLOOD_MARK_DURATION   : number = 8

-- VFX STUB â€” animator: water pool materialising on ground at target location, shimmering for duration
local function _VFX_FloodMark_Create(_pos: Vector3, _radius: number) end
local function _VFX_FloodMark_Expire(_pos: Vector3) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 5 â€” PRESSURE  (SelfBuff)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.2s cast. 6s flowing state: melee cannot be parried, all Tide abilities
--  apply Saturated on hit. On expiry: restore 15 Mana.

local PRESSURE_DURATION     : number = 6
local PRESSURE_MANA_RESTORE : number = 15

-- VFX STUB â€” animator: water constantly flowing around caster legs / arms during state
local function _VFX_Pressure_Enter(_caster: Player) end
local function _VFX_Pressure_Exit(_pos: Vector3) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVESET MODULE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local Tide = {
    AspectId    = "Tide",
    DisplayName = "Tide",
    Moves = {} :: any,
}

-- â”€â”€ Move 1 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            OnActivate    = nil, -- STUB â€” requires airborne dodge detection
        },
        {
            Id            = "SaturatingWave",
            Name          = "Saturating Wave",
            InteractsWith = "Saturated",
            Description   = "Current leaves a 4-stud wide wet zone along its path for 5s. "
                          .. "Targets moving through it gain Saturated (+25% Ember damage).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires zone creation along surge path
        },
        {
            Id            = "DrowningShore",
            Name          = "Drowning Shore",
            InteractsWith = "Breath",
            Description   = "Targets at â‰¤25% Breath when hit by Current are also Dampened (2s). "
                          .. "Punishes Breath-exhausted opponents who are overcommitted.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Breath attribute check at hit time
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

        local midPos    = origin + direction * (CURRENT_RANGE / 2)

        -- Use HitboxService for physical collision detection
        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        pcall(function()
            local PostureService = require(game:GetService("ServerScriptService").Server.services.PostureService)
            
            HitboxService.CreateHitbox({
                Shape = "Cylinder",
                Owner = player,
                Position = midPos,
                CFrame = CFrame.lookAt(midPos, tipPos) * CFrame.Angles(math.pi/2, 0, 0),
                Radius = CURRENT_RADIUS,
                Size = Vector3.new(0, CURRENT_RANGE, 0), -- Y is used for height
                Damage = CURRENT_POSTURE_DMG,
                LifeTime = 0.5,
                CanHitTwice = false,
                OnHit = function(target: any)
                    local tPlayer = typeof(target) == "Instance" and target:IsA("Player") and target or nil
                    if tPlayer then
                        -- #157: ability hits fill target posture and deal HP
                        PostureService.GainPosture(tPlayer, CURRENT_POSTURE_DMG)
                        local ok2, CS = pcall(function()
                            return require(game:GetService("ServerScriptService").Server.services.CombatService)
                        end)
                        if ok2 and CS then
                            CS.ApplyBreakDamage(tPlayer, CURRENT_HP_DMG)
                        end
                        _applyKnockbackAndMonitor(player, tPlayer, direction)
                    elseif type(target) == "string" then
                        -- Dummy hit: HP damage only (posture handled by server-loop?)
                        local DummyService = require(game:GetService("ServerScriptService").Server.services.DummyService)
                        DummyService.ApplyDamage(target, CURRENT_HP_DMG, root.Position)
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

-- â”€â”€ Move 2 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                          .. "(3s â†’ 6s). Saturated + Undertow removes mobility for a full engagement window.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Saturated status check at hit time
        },
        {
            Id            = "TidalLock",
            Name          = "Tidal Lock",
            InteractsWith = "Posture",
            Description   = "After Undertow lands, your next attack within 2s cannot be blocked â€” "
                          .. "target is off-balance. The anti-block window rewards immediate follow-up.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires temporary block-immunity attribute on caster
        },
        {
            Id            = "SurfaceTension",
            Name          = "Surface Tension",
            InteractsWith = "Grounded",
            Description   = "If the pulled target passes over a wet zone during pull, "
                          .. "they gain Grounded instead of Slow. Requires Current setup.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires wet zone detection during pull path
        },
    },

    VFX_Function = function(_caster: Player, _targetPos: Vector3?)
        -- VFX STUB â€” animator: pulling water stream from target to caster over 0.3s
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local myPos = root.Position
        local direction = root.CFrame.LookVector
        
        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        
        local pulled = false
        HitboxService.CreateHitbox({
            Shape = "Raycast",
            Owner = player,
            Origin = myPos,
            Direction = direction,
            Length = UNDERTOW_BASE_RANGE,
            Damage = 0,
            LifeTime = 0.2,
            CanHitTwice = false,
            OnHit = function(target: any)
                if pulled then return end
                
                local tChar = nil
                local tPlayer = nil
                if typeof(target) == "Instance" and target:IsA("Player") then
                    tChar = target.Character
                    tPlayer = target
                elseif type(target) == "string" then
                    tChar = workspace:FindFirstChild("Dummy_" .. target)
                end
                
                if not tChar then return end
                local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if not tRoot then return end
                
                pulled = true

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
                    -- TALENT HOOK STUB: FloodSense â€” if Saturated, double slow duration
                    -- TALENT HOOK STUB: TidalLock â€” grant caster block-bypass for 2s
                    -- TALENT HOOK STUB: SurfaceTension â€” if wet zone crossed, Grounded instead
                    task.delay(slowDur, function()
                        if tChar and tChar.Parent then
                            tChar:SetAttribute("StatusSlow", nil)
                            tChar:SetAttribute("SlowExpiry", nil)
                        end
                    end)
                end)

                _VFX_Undertow(myPos, tRoot.Position)
            end
        })
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Undertow", TargetPosition = targetPosition }) end
    end,
}

-- â”€â”€ Move 3 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            Description   = "If Swell releases at â‰¥2Ã— Momentum, pushback range increases from "
                          .. "3 to 7 studs and applies Slow (1s). Punishes aggressive Momentum builds.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Momentum check at release time
        },
        {
            Id            = "DeepBreath",
            Name          = "Deep Breath",
            InteractsWith = "Breath",
            Description   = "Swell's 2s window also fully restores your Breath pool. "
                          .. "The defensive window is also a breath reset â€” enables movement burst immediately.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Breath attribute full restore on activation
        },
        {
            Id            = "ReflectCurrent",
            Name          = "Reflect Current",
            InteractsWith = "Slow (incoming)",
            Description   = "If you are Slowed when Swell activates, the Slow is transferred to "
                          .. "all targets within 4 studs on activation. Counter-tool against Ash/Tide.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Slow status check + transfer on cast
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

        -- TALENT HOOK STUB: DeepBreath â€” restore Breath immediately
        -- TALENT HOOK STUB: ReflectCurrent â€” if Slowed, transfer Slow to nearby targets

        local function releaseSwell()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusSwell", nil)
            char:SetAttribute("SwellHitsRemaining", nil)
            char:SetAttribute("SwellExpiry", nil)

            -- Restore 20% max Posture (PostureService reads attribute)
            char:SetAttribute("PostureRestore", SWELL_POSTURE_RESTORE)

            -- Pushback nearby targets
            local myPos = root.Position
            local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
            HitboxService.CreateHitbox({
                Shape = "Circle",
                Radius = SWELL_PUSHBACK_RADIUS,
                Owner = player,
                Position = myPos,
                Damage = 0,
                LifeTime = 0.2,
                CanHitTwice = false,
                OnHit = function(target: any)
                    local tChar = nil
                    if typeof(target) == "Instance" and target:IsA("Player") then
                        tChar = target.Character
                    elseif type(target) == "string" then
                        tChar = workspace:FindFirstChild("Dummy_" .. target)
                    end
                    if not tChar then return end
                    local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not tRoot then return end

                    local hitDir = (tRoot.Position - myPos)
                    if hitDir.Magnitude < 0.001 then hitDir = Vector3.new(1,0,0) end
                    local pushDir = hitDir.Unit
                    tRoot.AssemblyLinearVelocity = pushDir * SWELL_PUSHBACK_DIST * 15
                    -- TALENT HOOK STUB: TidalSurge â€” if Momentum â‰¥2Ã—, extend to 7 studs + Slow
                end
            })
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

-- â”€â”€ Move 4 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            OnActivate    = nil, -- STUB â€” requires zone-hit event in CombatService
        },
        {
            Id            = "RisingTide",
            Name          = "Rising Tide",
            InteractsWith = "Posture",
            Description   = "While standing in your own Flood Mark zone, your Posture regen rate "
                          .. "is doubled instead of halved. Positional advantage.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires zone ownership tracking in PostureService
        },
        {
            Id            = "PhantomDepth",
            Name          = "Phantom Depth",
            InteractsWith = "Airborne",
            Description   = "Flood Mark zones pull airborne targets 2 studs downward when cast "
                          .. "directly below them, applying Grounded on landing. Limited anti-air.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires airborne detection at zone cast time
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
        local HitboxService = require(game:GetService("ReplicatedStorage").Shared.modules.HitboxService)
        HitboxService.CreateHitbox({
            Shape = "Circle",
            Radius = FLOOD_MARK_RADIUS,
            Owner = player,
            Position = targetPos,
            Damage = 0,
            LifeTime = 0.2,
            CanHitTwice = false,
            OnHit = function(target: any)
                local tChar = nil
                if typeof(target) == "Instance" and target:IsA("Player") then
                    tChar = target.Character
                elseif type(target) == "string" then
                    tChar = workspace:FindFirstChild("Dummy_" .. target)
                end
                if tChar then
                    tChar:SetAttribute("StatusSaturated", true)
                    -- TALENT HOOK STUB: PhantomDepth â€” if airborne, pull 2 studs down + Grounded
                end
            end
        })

        -- TALENT HOOK STUBS: StagnantPool â€” wire to CombatService hit events
        --                    RisingTide   â€” wire to PostureService regen calculation

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

-- â”€â”€ Move 5 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            OnActivate    = nil, -- STUB â€” requires Momentum attribute increment
        },
        {
            Id            = "FlowingForm",
            Name          = "Flowing Form",
            InteractsWith = "Slow (self)",
            Description   = "Tide abilities cast during Pressure cannot trigger Slow on yourself. "
                          .. "Removes one vulnerability during your offensive window.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires self-Slow immunity flag during state
        },
        {
            Id            = "UndertowPressure",
            Name          = "Undertow Pressure",
            InteractsWith = "Slow + Saturated",
            Description   = "Undertow cast during Pressure applies Saturated and Slow simultaneously. "
                          .. "Combo compressor â€” normally requires two casts.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Pressure state check in Undertow OnActivate
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
        -- TALENT HOOK STUB: CurrentState â€” increment Momentum attribute by 1
        -- TALENT HOOK STUB: FlowingForm  â€” set self-Slow immunity flag

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

-- ── Animations ──────────────────────────────────────────────────────────────
-- Primary animation source for Tide abilities. Move names match the ability
-- keys above. AnimationDatabase.Combat.Aspect.Tide is the fallback.
Tide.Animations = {
    Current     = "rbxassetid://0", -- STUB
    Undertow    = "rbxassetid://0", -- STUB
    Swell       = "rbxassetid://0", -- STUB
    FloodMark   = "rbxassetid://0", -- STUB
    Pressure    = "rbxassetid://0", -- STUB
}

return Tide
