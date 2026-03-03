--!strict
--[[
    Class: Void
    Description: VOID — Phase-based evasion, ability suppression, mark-hunting.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Anti-caster and lockdown. Counters resource-heavy opponents
                 by silencing, disrupting cooldowns, and burning through defences via Isolation.
    Issue: #149 — refactor Aspect system to full moveset
    Dependencies: none (server-only via OnActivate)

    Move list:
        [1] Blink          (UtilityProc) — Phase-teleport, posture debuff setup
        [2] Silence        (UtilityProc) — Ability lock on nearest target
        [3] PhaseShift     (Defensive)   — True invulnerability 0.6s + reposition
        [4] VoidPulse      (Offensive)   — Slow projectile, posture + regen interrupt
        [5] IsolationField (SelfBuff)    — Mark target: no healing + CDR slow + bonus dmg
]]

local Players = game:GetService("Players")

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 1 — BLINK (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  Instant cast. Phase-teleport up to 10 studs through geometry.
--  On arrival: interrupt target's Posture regen for 1s.
--  Next melee hit within 1.5s: +30% Posture damage.

local BLINK_RANGE           : number = 10
local BLINK_REGEN_INTERRUPT : number = 1     -- seconds of Posture regen block
local BLINK_BOOST_DURATION  : number = 1.5
local BLINK_POSTURE_BONUS   : number = 0.30

-- VFX STUB — animator: void/dark flash at origin, reappear with void ripple at dest
local function _VFX_Blink_Vanish(_origin: Vector3) end
local function _VFX_Blink_Arrive(_dest: Vector3) end
-- VFX STUB — animator: subtle dark shimmer on caster during melee boost window
local function _VFX_BlinkBoostActive(_caster: Player) end
local function _VFX_BlinkBoostExpire(_caster: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 2 — SILENCE (UtilityProc)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.15s cast. 8-stud pulse from caster. On hit: Silence 3s (random ability locked,
--  cannot be cast). 10 Posture damage. If target is mid-cast: cancel + trigger full CD.

local SILENCE_RANGE         : number = 8
local SILENCE_DURATION      : number = 3
local SILENCE_POSTURE_DMG   : number = 10

-- VFX STUB — animator: void pulse wave expands 8 studs, targets get dark orb mouth effect
local function _VFX_Silence_Pulse(_origin: Vector3) end
-- VFX STUB — animator: grey-out animation on one random slot in target's hotbar
local function _VFX_SilenceStatus(_target: Player, _lockedSlot: number) end
local function _VFX_SilenceExpire(_target: Player) end

-- Picks a random ability slot to lock (1-5; server authoritative)
local function _pickSilenceSlot(): number
    return math.random(1, 5)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 3 — PHASESHIFT (Defensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  Instant cast. True invulnerability 0.6s: untargetable, no damage, no state change.
--  On exit: reappear at position + 3-stud reposition in caster's movement direction.

local PHASESHIFT_DURATION   : number = 0.6
local PHASESHIFT_REPOSITION : number = 3

-- VFX STUB — animator: void cloak (invisible + dark outline), reappear with phase burst
local function _VFX_PhaseShift_Enter(_caster: Player) end
local function _VFX_PhaseShift_Exit(_caster: Player, _dest: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 4 — VOIDPULSE (Offensive)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.2s cast. Launches slow projectile (travels 12 studs over ~1s).
--  On hit: 30 Posture + 2s Posture-regen interrupt. Can be dodge-cancelled.
--  vs Silenced target: Posture doubles (60).

local VOIDPULSE_RANGE           : number = 12
local VOIDPULSE_SPEED           : number = 12  -- studs/s → 1s travel for 12 studs
local VOIDPULSE_POSTURE_DMG     : number = 30
local VOIDPULSE_REGEN_INTERRUPT : number = 2
local VOIDPULSE_RADIUS          : number = 2   -- hitbox on arrival

-- VFX STUB — animator: slow-moving dark orb with void ripples, detonates on hit
local function _VFX_VoidPulse_Spawn(_origin: Vector3, _dest: Vector3) end
local function _VFX_VoidPulse_Hit(_pos: Vector3) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVE 5 — ISOLATIONFIELD (SelfBuff)
-- ═════════════════════════════════════════════════════════════════════════════
--  0.3s cast. Mark target within 12 studs for 5s.
--  Effect: target receives no healing, their CDR rate slowed 50%,
--  and you deal +15% damage to them. Mark is dispelled if target leaves 20-stud radius.

local ISOLATION_RANGE       : number = 12
local ISOLATION_DURATION    : number = 5
local ISOLATION_DMG_BONUS   : number = 0.15
local ISOLATION_CDR_SLOW    : number = 0.50   -- CDR operates at 50% of normal rate
local ISOLATION_BREAK_RANGE : number = 20     -- mark breaks if target flees this far

-- VFX STUB — animator: dark void ring around target, caster has dark sigil on hand
local function _VFX_IsolationField_Apply(_target: Player) end
local function _VFX_IsolationField_Expire(_target: Player) end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVESET MODULE
-- ═════════════════════════════════════════════════════════════════════════════

local Void = {
    AspectId    = "Void",
    DisplayName = "Void",
    Moves       = {} :: any,
}

-- ── Move 1 ───────────────────────────────────────────────────────────────────
Void.Moves[1] = {
    Id          = "Blink",
    Name        = "Blink",
    AspectId    = "Void",
    Slot        = 1,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Phase-teleport up to 10 studs through geometry. "
                .. "Interrupt nearest target's Posture regen for 1s. "
                .. "Next melee hit within 1.5s deals +30% Posture damage.",

    CastTime         = 0.1,
    ManaCost         = 20,
    Cooldown         = 4,
    Range            = BLINK_RANGE,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping", "Attacking"},

    Talents = {
        {
            Id            = "Nullpoint",
            Name          = "Nullpoint",
            InteractsWith = "Posture Regen",
            Description   = "If Blink is cast within 3 studs of the target, the Posture regen "
                          .. "interrupt extends from 1s to 2.5s. Close-range phasing = deeper debuff.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires distance check at teleport arrival
        },
        {
            Id            = "PhaseResidue",
            Name          = "Phase Residue",
            InteractsWith = "Zone",
            Description   = "Blink origin leaves a Slow field (1s duration, 2-stud radius) at "
                          .. "departure point. Opponents chasing get briefly slowed.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Slow zone spawn at origin after teleport
        },
        {
            Id            = "VoidSlip",
            Name          = "Void Slip",
            InteractsWith = "Airborne",
            Description   = "If Blink is cast while airborne, range extends to 14 studs (+4). "
                          .. "Phase through geometry at greater horizontal distance.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne state → range override
        },
    },

    VFX_Function = function(caster: Player, targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        local dest = targetPos or (root.Position + root.CFrame.LookVector * BLINK_RANGE)
        _VFX_Blink_Vanish(root.Position)
        _VFX_Blink_Arrive(dest)
    end,

    OnActivate = function(player: Player, targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin  = root.Position
        local forward = root.CFrame.LookVector

        -- Determine destination (up to BLINK_RANGE studs)
        local rawDest = targetPos or (origin + forward * BLINK_RANGE)
        local delta   = rawDest - origin
        if delta.Magnitude > BLINK_RANGE then
            rawDest = origin + delta.Unit * BLINK_RANGE
        end

        _VFX_Blink_Vanish(origin)
        root.CFrame = CFrame.new(rawDest, rawDest + forward)
        _VFX_Blink_Arrive(rawDest)

        -- TALENT HOOK STUB: PhaseResidue — spawn Slow zone at `origin`
        -- TALENT HOOK STUB: VoidSlip     — if airborne, range was already 14 studs above

        -- Interrupt nearest target's Posture regen
        local bestDist = math.huge
        local bestChar: Model? = nil
        for _, target in Players:GetPlayers() do
            if target == player then continue end
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not tRoot then continue end
            local dist = (tRoot.Position - rawDest).Magnitude
            if dist < bestDist then
                bestDist = dist
                bestChar = tChar
            end
        end

        if bestChar then
            local interruptDur = BLINK_REGEN_INTERRUPT
            -- TALENT HOOK STUB: Nullpoint — if bestDist < 3, interruptDur = 2.5
            bestChar:SetAttribute("PostureRegenBlocked", true)
            bestChar:SetAttribute("PostureRegenBlockExpiry", tick() + interruptDur)
            task.delay(interruptDur, function()
                if bestChar and bestChar.Parent then
                    bestChar:SetAttribute("PostureRegenBlocked", nil)
                    bestChar:SetAttribute("PostureRegenBlockExpiry", nil)
                end
            end)
        end

        -- Melee boost window
        char:SetAttribute("StatusBlinkBoost", true)
        char:SetAttribute("BlinkBoostExpiry", tick() + BLINK_BOOST_DURATION)
        char:SetAttribute("BlinkPostureBonus", BLINK_POSTURE_BONUS)
        _VFX_BlinkBoostActive(player)
        task.delay(BLINK_BOOST_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusBlinkBoost", nil)
            char:SetAttribute("BlinkBoostExpiry", nil)
            char:SetAttribute("BlinkPostureBonus", nil)
            _VFX_BlinkBoostExpire(player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Blink", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 2 ───────────────────────────────────────────────────────────────────
Void.Moves[2] = {
    Id          = "Silence",
    Name        = "Silence",
    AspectId    = "Void",
    Slot        = 2,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "8-stud pulse from caster. Nearest target hit: Silence 3s (random ability locked). "
                .. "10 Posture damage. If target is mid-cast: cancel their cast + trigger full CD.",

    CastTime         = 0.15,
    ManaCost         = 20,
    Cooldown         = 9,
    Range            = SILENCE_RANGE,
    PostureDamage    = SILENCE_POSTURE_DMG,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Attacking"},

    Talents = {
        {
            Id            = "EchoSilence",
            Name          = "Echo Silence",
            InteractsWith = "Mana",
            Description   = "While a target is Silenced, their CDR is suppressed. For every second "
                          .. "they cannot use the locked ability, you gain +5 Mana (max 15 per cast).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires per-second Mana drain from Silenced CDR
        },
        {
            Id            = "VoidHunger",
            Name          = "Void Hunger",
            InteractsWith = "Blocking",
            Description   = "If target is Blocking when hit by Silence, the block is broken "
                          .. "and full Posture drain applies (not the reduced block Posture).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires block state check → block break at impact
        },
        {
            Id            = "StillZone",
            Name          = "Still Zone",
            InteractsWith = "Zone",
            Description   = "On hit, a void field (3s) spawns at impact: ability range -50% "
                          .. "for any player inside. Spatial suppression zone.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires zone spawn with range debuff attribute
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        _VFX_Silence_Pulse(root.Position)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin = root.Position
        _VFX_Silence_Pulse(origin)

        -- Find nearest target in range
        local bestDist = math.huge
        local bestTarget: Player? = nil
        local bestChar: Model? = nil
        for _, target in Players:GetPlayers() do
            if target == player then continue end
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not tRoot then continue end
            local dist = (tRoot.Position - origin).Magnitude
            if dist <= SILENCE_RANGE and dist < bestDist then
                bestDist  = dist
                bestTarget = target
                bestChar   = tChar
            end
        end

        if not bestTarget or not bestChar then return end

        -- Posture damage
        bestChar:SetAttribute("IncomingPostureDamage",
            (bestChar:GetAttribute("IncomingPostureDamage") or 0) + SILENCE_POSTURE_DMG)
        bestChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_Silence")

        -- Cancel mid-cast (signal: server checks CastingAbility attribute)
        if bestChar:GetAttribute("CastingAbility") then
            bestChar:SetAttribute("CastInterrupted", true)
            bestChar:SetAttribute("CastingAbility", nil)
        end

        -- TALENT HOOK STUB: VoidHunger — if Blocking, break block + full posture drain

        -- Apply Silence
        local lockedSlot = _pickSilenceSlot()
        bestChar:SetAttribute("StatusSilenced", true)
        bestChar:SetAttribute("SilenceExpiry", tick() + SILENCE_DURATION)
        bestChar:SetAttribute("SilencedSlot", lockedSlot)
        _VFX_SilenceStatus(bestTarget, lockedSlot)

        -- TALENT HOOK STUB: EchoSilence — per-second Mana gain while target is Silenced
        -- TALENT HOOK STUB: StillZone   — spawn range-reduction zone at bestChar position

        task.delay(SILENCE_DURATION, function()
            if not bestChar or not bestChar.Parent then return end
            bestChar:SetAttribute("StatusSilenced", nil)
            bestChar:SetAttribute("SilenceExpiry", nil)
            bestChar:SetAttribute("SilencedSlot", nil)
            _VFX_SilenceExpire(bestTarget :: Player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Silence", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 3 ───────────────────────────────────────────────────────────────────
Void.Moves[3] = {
    Id          = "PhaseShift",
    Name        = "Phase Shift",
    AspectId    = "Void",
    Slot        = 3,
    Type        = "Expression",
    MoveType    = "Defensive",
    Description = "0.6s true invulnerability — untargetable, no damage, no state override. "
                .. "On exit: reappear at origin + 3-stud reposition in movement direction.",

    CastTime         = 0,        -- instant
    ManaCost         = 25,
    Cooldown         = 11,
    Range            = nil,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping", "Attacking", "Stunned"},

    Talents = {
        {
            Id            = "PhaseEcho",
            Name          = "Phase Echo",
            InteractsWith = "Posture",
            Description   = "On exiting PhaseShift, restore 15 Posture to caster. "
                          .. "Framing a phase correctly recovers defensive resources.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Posture restore on phase exit
        },
        {
            Id            = "VoidExit",
            Name          = "Void Exit",
            InteractsWith = "Airborne",
            Description   = "If PhaseShift exits airborne (caster jumped before cast), emit "
                          .. "a 4-stud Slow burst on reappearance. Aerial phase = zoning tool.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires airborne check at exit + Slow burst
        },
        {
            Id            = "NullState",
            Name          = "Null State",
            InteractsWith = "Stagger",
            Description   = "Phase cast during a Stagger window negates the Stagger and enters "
                          .. "PhaseShift instead. Only once per engagement. Panic-button vs Break.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Stagger intercept at cast time (once-per)
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        _VFX_PhaseShift_Enter(caster)
    end,

    OnActivate = function(player: Player, _targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        -- Enter phase — untargetable flag (read by CombatService)
        char:SetAttribute("StatusPhaseShift", true)
        char:SetAttribute("PhaseShiftExpiry", tick() + PHASESHIFT_DURATION)
        _VFX_PhaseShift_Enter(player)

        -- TALENT HOOK STUB: NullState — if in Stagger, intercept and negate it
        -- TALENT HOOK STUB: VoidExit  — check if airborne at exit for Slow burst

        task.delay(PHASESHIFT_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusPhaseShift", nil)
            char:SetAttribute("PhaseShiftExpiry", nil)

            -- Reposition in movement direction
            if root and root.Parent then
                local vel   = root.AssemblyLinearVelocity
                local moveDir = Vector3.new(vel.X, 0, vel.Z)
                local dest: Vector3
                if moveDir.Magnitude > 0.5 then
                    dest = root.Position + moveDir.Unit * PHASESHIFT_REPOSITION
                else
                    dest = root.Position + root.CFrame.LookVector * PHASESHIFT_REPOSITION
                end
                root.CFrame = CFrame.new(dest, dest + root.CFrame.LookVector)
                _VFX_PhaseShift_Exit(player, dest)

                -- TALENT HOOK STUB: PhaseEcho — restore 15 Posture on exit
                -- TALENT HOOK STUB: VoidExit  — if airborne, Slow burst 4 studs
            end
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "PhaseShift", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 4 ───────────────────────────────────────────────────────────────────
Void.Moves[4] = {
    Id          = "VoidPulse",
    Name        = "Void Pulse",
    AspectId    = "Void",
    Slot        = 4,
    Type        = "Expression",
    MoveType    = "Offensive",
    Description = "Cast a slow projectile (12 studs, ~1s travel). On hit: 30 Posture "
                .. "+ 2s Posture regen interrupt. Can be dodge-cancelled. "
                .. "vs Silenced target: Posture doubles (60). Blink in last 2s → instant cast.",

    CastTime         = 0.2,
    ManaCost         = 20,
    Cooldown         = 8,
    Range            = VOIDPULSE_RANGE,
    PostureDamage    = VOIDPULSE_POSTURE_DMG,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Jumping"},

    Talents = {
        {
            Id            = "GravityWell",
            Name          = "Gravity Well",
            InteractsWith = "Airborne",
            Description   = "If VoidPulse hits a target at 30°+ upward angle (airborne), "
                          .. "they are pulled down and Grounded on landing. Anti-air punish.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Y-angle check at impact + Grounded on land
        },
        {
            Id            = "ResonanceDrain",
            Name          = "Resonance Drain",
            InteractsWith = "Resonance",
            Description   = "VoidPulse hit reduces target's current Resonance streak timer "
                          .. "by 5s. Slows their Resonance accumulation without negating it.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires ResonanceStreakTimer attribute decrement
        },
        {
            Id            = "PhaseChain",
            Name          = "Phase Chain",
            InteractsWith = "Blink",
            Description   = "If Blink was used in the last 2s, VoidPulse ignores cast time "
                          .. "and fires instantly. Phase in + Pulse out = seamless combo.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires BlinkLastUsed timestamp check at cast
        },
    },

    VFX_Function = function(caster: Player, targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        local dest = targetPos or (root.Position + root.CFrame.LookVector * VOIDPULSE_RANGE)
        _VFX_VoidPulse_Spawn(root.Position, dest)
    end,

    OnActivate = function(player: Player, targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin  = root.Position
        local forward = root.CFrame.LookVector
        local dest    = targetPos or (origin + forward * VOIDPULSE_RANGE)

        -- TALENT HOOK STUB: PhaseChain — if Blink within last 2s, skip cast time (instant)

        _VFX_VoidPulse_Spawn(origin, dest)

        -- Simulate slow projectile travel
        local travelTime = VOIDPULSE_RANGE / VOIDPULSE_SPEED
        task.delay(travelTime, function()
            if not char or not char.Parent then return end

            _VFX_VoidPulse_Hit(dest)

            -- Hit detection at destination
            for _, target in Players:GetPlayers() do
                if target == player then continue end
                local tChar = target.Character
                if not tChar then continue end
                local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if not tRoot then continue end
                if (tRoot.Position - dest).Magnitude > VOIDPULSE_RADIUS then continue end

                -- Check Silenced: double posture
                local silenced    = tChar:GetAttribute("StatusSilenced") == true
                local postureDmg  = silenced and (VOIDPULSE_POSTURE_DMG * 2) or VOIDPULSE_POSTURE_DMG

                tChar:SetAttribute("IncomingPostureDamage",
                    (tChar:GetAttribute("IncomingPostureDamage") or 0) + postureDmg)
                tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_VoidPulse")

                -- Posture regen interrupt
                tChar:SetAttribute("PostureRegenBlocked", true)
                tChar:SetAttribute("PostureRegenBlockExpiry", tick() + VOIDPULSE_REGEN_INTERRUPT)
                task.delay(VOIDPULSE_REGEN_INTERRUPT, function()
                    if tChar and tChar.Parent then
                        tChar:SetAttribute("PostureRegenBlocked", nil)
                        tChar:SetAttribute("PostureRegenBlockExpiry", nil)
                    end
                end)

                -- TALENT HOOK STUB: GravityWell    — if airborne at impact, Grounded on land
                -- TALENT HOOK STUB: ResonanceDrain — decrement ResonanceStreakTimer -5s
            end
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "VoidPulse", TargetPosition = targetPosition }) end
    end,
}

-- ── Move 5 ───────────────────────────────────────────────────────────────────
Void.Moves[5] = {
    Id          = "IsolationField",
    Name        = "Isolation Field",
    AspectId    = "Void",
    Slot        = 5,
    Type        = "Expression",
    MoveType    = "SelfBuff",
    Description = "Mark target within 12 studs for 5s: they receive no healing, "
                .. "their CDR is slowed 50%, and you deal +15% damage to them. "
                .. "Mark breaks if target leaves a 20-stud radius.",

    CastTime         = 0.3,
    ManaCost         = 30,
    Cooldown         = 18,
    Range            = ISOLATION_RANGE,
    PostureDamage    = nil,
    BaseDamage       = nil,
    RequiredState    = {"Idle", "Walking", "Running", "Attacking"},

    Talents = {
        {
            Id            = "NullResonance",
            Name          = "Null Resonance",
            InteractsWith = "Resonance",
            Description   = "During Isolation, the target's Resonance glow is suppressed and "
                          .. "their Resonance burst threshold is paused (glow hidden for 5s).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires ResonanceGlow boolean attribute suppression
        },
        {
            Id            = "PhaseLock",
            Name          = "Phase Lock",
            InteractsWith = "Blink",
            Description   = "While Isolation is active on a target, Blink cooldown is halved to 2s. "
                          .. "Press the advantage — phase aggressively while mark is up.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Blink CD override attribute while mark active
        },
        {
            Id            = "VoidFeeding",
            Name          = "Void Feeding",
            InteractsWith = "Silence",
            Description   = "If Silence is active on the marked target simultaneously, CDR slow "
                          .. "increases to 75% and damage bonus increases to 25%. Double suppression.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB — requires Silence + Isolation simultaneous check
        },
    },

    VFX_Function = function(caster: Player, _targetPos: Vector3?)
        local char = caster.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end
        -- VFX are applied to target — done inside OnActivate
    end,

    OnActivate = function(player: Player, targetPos: Vector3?)
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return end

        local origin = root.Position

        -- Find nearest valid target within ISOLATION_RANGE
        local bestDist   = math.huge
        local bestTarget : Player? = nil
        local bestChar   : Model? = nil
        for _, target in Players:GetPlayers() do
            if target == player then continue end
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not tRoot then continue end
            local dist = (tRoot.Position - origin).Magnitude
            if dist <= ISOLATION_RANGE and dist < bestDist then
                bestDist   = dist
                bestTarget = target
                bestChar   = tChar
            end
        end

        if not bestTarget or not bestChar then return end

        -- Apply mark attributes to target
        local markKey = "IsolationMarkedBy_" .. player.Name
        bestChar:SetAttribute(markKey, true)
        bestChar:SetAttribute("IsolationMarkExpiry", tick() + ISOLATION_DURATION)
        bestChar:SetAttribute("StatusNoHealing", true)
        bestChar:SetAttribute("CDRSlow", ISOLATION_CDR_SLOW)

        -- Caster attribute for damage bonus lookup
        char:SetAttribute("IsolationTarget", (bestTarget :: Player).Name)
        char:SetAttribute("IsolationDamageBonus", ISOLATION_DMG_BONUS)
        char:SetAttribute("IsolationExpiry", tick() + ISOLATION_DURATION)

        _VFX_IsolationField_Apply(bestTarget :: Player)

        -- TALENT HOOK STUB: NullResonance — suppress ResonanceGlow attribute on target
        -- TALENT HOOK STUB: PhaseLock     — set BlinkCDOverride = 2 on caster
        -- TALENT HOOK STUB: VoidFeeding   — if target Silenced, escalate values

        -- Monitor: break if target flees > ISOLATION_BREAK_RANGE
        local function _monitor()
            local elapsed = 0
            while elapsed < ISOLATION_DURATION do
                task.wait(0.1)
                elapsed += 0.1
                if not bestChar or not bestChar.Parent then break end
                if not root or not root.Parent then break end
                local tRoot2 = bestChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if not tRoot2 then break end
                if (tRoot2.Position - root.Position).Magnitude > ISOLATION_BREAK_RANGE then
                    break  -- mark broken by distance
                end
            end
            -- Expire mark
            if bestChar and bestChar.Parent then
                bestChar:SetAttribute(markKey, nil)
                bestChar:SetAttribute("IsolationMarkExpiry", nil)
                bestChar:SetAttribute("StatusNoHealing", nil)
                bestChar:SetAttribute("CDRSlow", nil)
                _VFX_IsolationField_Expire(bestTarget :: Player)
            end
            if char and char.Parent then
                char:SetAttribute("IsolationTarget", nil)
                char:SetAttribute("IsolationDamageBonus", nil)
                char:SetAttribute("IsolationExpiry", nil)
            end
        end
        task.spawn(_monitor)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "IsolationField", TargetPosition = targetPosition }) end
    end,
}


-- ─── VFX stubs ───────────────────────────────────────────────────────────────

local function _VFX_BlinkDissolve(_origin: Vector3)
    -- VFX STUB — animator: void-ripple dissolve at origin, 0.05s
end

local function _VFX_BlinkArrive(_dest: Vector3)
    -- VFX STUB — animator: dark void-particle burst at dest, 0.1s
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

--[[
    _findNearestTarget(caster, position) → (Player?, Vector3?)
    Finds the closest enemy player within TARGET_SEEK_RADIUS.
    Returns the player and their character root position, or nil if none found.
]]
local function _findNearestTarget(caster: Player, position: Vector3): (Player?, Vector3?)
    local bestDist = TARGET_SEEK_RADIUS + 1
    local bestPlayer: Player? = nil
    local bestPos: Vector3? = nil

    for _, target in Players:GetPlayers() do
        if target == caster then continue end
        local char = target.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then continue end
        local d = (root.Position - position).Magnitude
        if d < bestDist then
            bestDist = d
            bestPlayer = target
            bestPos = root.Position
        end
    end

    return bestPlayer, bestPos
end

--[[
    _computeDestination(caster, root) → Vector3
    If a target is within range, returns a position 2 studs behind them.
    Otherwise returns a point BLINK_DISTANCE studs forward (line-of-sight blink).
    Does NOT do geometry collision filtering — the issue spec says "through geometry".
]]
local function _computeDestination(root: BasePart): Vector3
    local casterPos = root.Position
    local casterPlayer: Player? = nil
    for _, p in Players:GetPlayers() do
        if p.Character and p.Character:FindFirstChild("HumanoidRootPart") == root then
            casterPlayer = p
            break
        end
    end

    if casterPlayer then
        local target, targetPos = _findNearestTarget(casterPlayer, casterPos)
        if target and targetPos then
            local targetChar   = target.Character :: Model
            local targetRoot   = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart
            local targetForward = targetRoot.CFrame.LookVector
            -- Position: behind target (opposite of their look vector) + slight Y align
            return targetPos - targetForward * BEHIND_OFFSET + Vector3.new(0, 0.05, 0)
        end
    end

    -- No target — linear blink forward
    return casterPos + root.CFrame.LookVector * BLINK_DISTANCE
end

--[[
    _interruptPostureRecovery(target, char, duration)
    Sets a character attribute that PostureService checks to suppress regen.
    Auto-clears after duration.
]]
local function _interruptPostureRecovery(target: Player, char: Model, duration: number)
    -- PostureService reads "PostureRegenBlocked" and skips regen while true
    char:SetAttribute("PostureRegenBlocked", true)
    char:SetAttribute("PostureRegenBlockExpiry", tick() + duration)

    -- TALENT HOOK STUB: Nullpoint — if target is Staggered, also silence one ability
    -- local isStaggered = char:GetAttribute("Staggered")
    -- if isStaggered then ... end

    task.delay(duration, function()
        if char and char.Parent then
            local expiry = char:GetAttribute("PostureRegenBlockExpiry") :: number?
            if expiry and tick() >= expiry then
                char:SetAttribute("PostureRegenBlocked", nil)
                char:SetAttribute("PostureRegenBlockExpiry", nil)
            end
        end
    end)

    print(("[Blink] Posture recovery interrupted — %s (%.1fs)"):format(target.Name, duration))
end

--[[
    _grantVoidPostureBonus(caster, char)
    Sets a charge on the caster's character that their NEXT melee hit reads.
    CombatService should check VoidPostureBonusCharge > 0 and add VOID_POSTURE_BONUS
    to posture damage, then consume the charge.
]]
local function _grantVoidPostureBonus(char: Model)
    char:SetAttribute("VoidPostureBonusCharge", VOID_POSTURE_BONUS)
    char:SetAttribute("VoidPostureBonusExpiry", tick() + VOID_BONUS_WINDOW)

    -- Auto-expire the charge if unused
    task.delay(VOID_BONUS_WINDOW, function()
        if char and char.Parent then
            local expiry = char:GetAttribute("VoidPostureBonusExpiry") :: number?
            if expiry and tick() >= expiry then
                char:SetAttribute("VoidPostureBonusCharge", nil)
                char:SetAttribute("VoidPostureBonusExpiry", nil)
            end
        end
    end)

    print(("[Blink] VoidPostureBonus charge granted (+%d posture on next melee)"):format(
        VOID_POSTURE_BONUS))
end

-- ─── OnActivate ──────────────────────────────────────────────────────────────

function Void.OnActivate(player: Player, _targetPos: Vector3?)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local origin = root.Position
    local dest   = _computeDestination(root)

    -- TALENT HOOK STUB: Void Slip — if airborne, offset dest +3Y above target
    -- TALENT HOOK STUB: Phase Residue — grant Dampened-immunity for 0.5s

    _VFX_BlinkDissolve(origin)

    -- Teleport (instant)
    root.CFrame = CFrame.new(dest, dest + root.CFrame.LookVector)
    _VFX_BlinkArrive(dest)

    -- Grant posture bonus charge to caster
    _grantVoidPostureBonus(char)

    -- Find target at destination to interrupt posture recovery
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = { char }

    local nearby = Workspace:GetPartBoundsInRadius(dest, BEHIND_OFFSET + 1, overlapParams)
    local interrupted: {[Player]: boolean} = {}

    for _, hit in nearby do
        local model = hit:FindFirstAncestorOfClass("Model")
        if not model then continue end
        for _, target in Players:GetPlayers() do
            if target == player then continue end
            if interrupted[target] then continue end
            if target.Character == model then
                interrupted[target] = true
                _interruptPostureRecovery(target, model, POSTURE_RECOVERY_BLOCK)
            end
        end
    end

    print(("[Blink] %s teleported %.1f studs"):format(
        player.Name, (dest - origin).Magnitude))
end

-- ─── ClientActivate ──────────────────────────────────────────────────────────

function Void.ClientActivate(targetPosition: Vector3?)
    local np = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
    local remote = np:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({ AbilityId = Void.Id, TargetPosition = targetPosition })
    end
end

return Void
