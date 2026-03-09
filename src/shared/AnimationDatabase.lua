--!strict
--[[
    Module: AnimationDatabase
    Description: Central registry of animation asset IDs, organized by category.
                 Consumed by AnimationLoader which flattens this table at require-time
                 and resolves single-animation lookups (movement states, ability casts)
                 directly from rbxassetid strings.

    ── KEY RULES ──────────────────────────────────────────────────────────────
    1. Every leaf key in this table MUST be globally unique — AnimationLoader
       flattens the entire tree into a single { [string]: string } map.
    2. IDs marked "STUB" are placeholders. Replace with the real rbxassetid
       before shipping the feature. Create a spec-gap issue for each.
    3. Weapon animations are NOT in this table. Weapons use the Folder/Asset
       registry pattern inside src/shared/weapons/ and are fetched from
       ReplicatedStorage.animations via folder lookup. Putting weapon assets
       here would collide with shared key names (e.g. "Idle", "Walk").

    Usage:
        local AnimDB = require(ReplicatedStorage.Shared.AnimationDatabase)
        local idle = AnimDB.Movement.Idle   -- "rbxassetid://14318992100"
]]

-- Flat key into the database; resolved by AnimationLoader
export type AnimationKey = string

-- Per-ability animation map inside an Aspect block
export type AnimationAspectMoves = { [string]: string }

export type AnimationDatabaseT = {
    Movement : { [string]: string },
    Combat   : {
        -- aspect name  →  move name  →  rbxassetid
        Aspect  : { [string]: AnimationAspectMoves },
        -- shared combat animations not tied to a specific weapon or aspect
        General : { [string]: string },
    },
    UI       : { [string]: string },
}

local AnimationDatabase: AnimationDatabaseT = {

    -- ══════════════════════════════════════════════════════════════════════
    --  MOVEMENT
    --  Keys are the exact strings passed to AnimationLoader.LoadTrack()
    --  from MovementController and DummyController.
    -- ══════════════════════════════════════════════════════════════════════
    Movement = {

        -- ── Grounded locomotion (real IDs) ──────────────────────────────
        -- Sprint / Run / Running all share the same locomotion animation.
        -- Three keys exist because MovementController passes all three strings.
        Idle        = "rbxassetid://14318992100",
        Walk        = "rbxassetid://14319000969",
        Run         = "rbxassetid://14318999286",
        Running     = "rbxassetid://14318999286", -- same as Run (MovementController state string)
        Sprint      = "rbxassetid://14318999286", -- same as Run (higher-speed state string)

        -- Dash reuses the FrontRoll animation — same motion, same asset.
        Dash        = "rbxassetid://14318990130", -- = FrontRoll

        -- ── Airborne ────────────────────────────────────────────────────
        Jump        = "rbxassetid://140102262721264",-- STUB (#jump-anim): rising + peak loop
        AirFall     = "rbxassetid://0",           -- STUB (#airfall-anim): falling descent

        -- ── Rolls (real IDs) ────────────────────────────────────────────
        -- NOTE: Dash (above) also uses FrontRoll's ID — same motion.
        FrontRoll   = "rbxassetid://14318990130",
        BackRoll    = "rbxassetid://14318987482",
        RightRoll   = "rbxassetid://14318997648",
        LeftRoll    = "rbxassetid://14318995205",

        -- ── Traversal ───────────────────────────────────────────────────
        Slide       = "rbxassetid://80839539293697",           -- STUB (#slide-anim)
        SlideJump   = "rbxassetid://0",           -- STUB (#slidejump-anim): jump out of slide
        WallRun     = "rbxassetid://0",           -- STUB (#wallrun-anim): currently aliases "Running"
        Vault       = "rbxassetid://98551287074212",           -- STUB (#vault-anim): obstacle vault
        Climb       = "rbxassetid://112751946477135",           -- STUB (#climb-anim): surface grip climb
        LedgeHold   = "rbxassetid://90143860242624",           -- STUB (#ledgehold-anim): hanging idle
        LedgeClimb  = "rbxassetid://105955004934707",           -- STUB (#ledgeclimb-anim): pull-up

        Landing     = "rbxassetid://83702450284435",           -- STUB (#landing-anim): impact landing from fall/jump

        -- ── Crouch (locomotion reference — see Combat.General.CrouchIdle for real ID) ──
        -- NOTE: "Crouching" key lives in Combat.General to avoid flat-map collision.
        --       MovementController does not use "Crouching" as an anim state.
    },

    Combat = {

        -- ══════════════════════════════════════════════════════════════════
        --  ASPECT ABILITIES
        --  Structure: Combat.Aspect[AspectName][MoveName]
        --  Move names match the constants in src/shared/abilities/*.lua.
        --  All STUBs: replace IDs when animations are authored.
        -- ══════════════════════════════════════════════════════════════════
        Aspect = {

            -- ── ASH ─ Misdirection, patience, information advantage ──────
            -- Move list: AshenStep, CinderBurst, Fade, Trace, GreyVeil
            Ash = {
                AshenStep       = "rbxassetid://0", -- STUB: forward dash with ash-smoke trail
                CinderBurst     = "rbxassetid://0", -- STUB: point-blank cone burst stance
                Fade            = "rbxassetid://0", -- STUB: reactive vanish/escape
                Trace           = "rbxassetid://0", -- STUB: mark-placement gesture
                GreyVeil        = "rbxassetid://0", -- STUB: self-buff concealment pose
            },

            -- ── GALE ─ Aerial control, vertical pressure, zone disruption ─
            -- Move list: WindStrike, Crosswind, Windwall, Updraft, Shear
            Gale = {
                WindStrike      = "rbxassetid://0", -- STUB: dash launch upward
                Crosswind       = "rbxassetid://0", -- STUB: lateral push cast
                Windwall        = "rbxassetid://0", -- STUB: barrier raise stance
                Updraft         = "rbxassetid://0", -- STUB: vertical self-launch
                Shear           = "rbxassetid://0", -- STUB: 180° arc sweep
            },

            -- ── TIDE ─ Resource denial, terrain control, sustained pressure
            -- Move list: Current, Undertow, Swell, FloodMark, Pressure
            Tide = {
                Current         = "rbxassetid://0", -- STUB: ranged surge cast
                Undertow        = "rbxassetid://0", -- STUB: pull animation
                Swell           = "rbxassetid://0", -- STUB: defensive shell activation
                FloodMark       = "rbxassetid://0", -- STUB: area-mark placement
                Pressure        = "rbxassetid://0", -- STUB: parry-window stance
            },

            -- ── EMBER ─ Stack-based escalation, aggressive commitment ─────
            -- Move list: Ignite, Flashfire, HeatShield, Surge, CinderField
            Ember = {
                Ignite          = "rbxassetid://0", -- STUB: ember-trail dash
                Flashfire       = "rbxassetid://0", -- STUB: AoE detonation stance
                HeatShield      = "rbxassetid://0", -- STUB: absorb guard raise
                Surge           = "rbxassetid://0", -- STUB: momentum burst pose
                CinderField     = "rbxassetid://0", -- STUB: ground-slam zone placement
            },

            -- ── VOID ─ Phase evasion, ability suppression, mark-hunting ───
            -- Move list: Blink, Silence, PhaseShift, VoidPulse, IsolationField
            Void = {
                Blink           = "rbxassetid://0", -- STUB: phase-teleport vanish/arrive
                Silence         = "rbxassetid://0", -- STUB: void-pulse cast
                PhaseShift      = "rbxassetid://0", -- STUB: invulnerability phase pose
                VoidPulse       = "rbxassetid://0", -- STUB: slow projectile throw
                IsolationField  = "rbxassetid://0", -- STUB: target-mark gesture
            },
        },

        -- ══════════════════════════════════════════════════════════════════
        --  GENERAL COMBAT
        --  Shared animations not bound to a specific weapon or aspect.
        -- ══════════════════════════════════════════════════════════════════
        General = {

            -- ── Fist strikes (real IDs) ──────────────────────────────────
            -- NOTE: weapon combo playback uses Folder="Fists", Asset="punch N" via
            -- folder lookup. These keys are for direct single-animation calls only.
            Punch1      = "rbxassetid://14319068127",
            Punch2      = "rbxassetid://14319069377",
            Punch3      = "rbxassetid://14319070179",
            Punch4      = "rbxassetid://14319071027",
            Punch5      = "rbxassetid://14319071645",
            -- Convenience alias used in ActionTypes.lua default configs
            Fists       = "rbxassetid://14319068127", -- → Punch1

            -- ── Generic strikes (real IDs) ───────────────────────────────
            SlamDown    = "rbxassetid://14319072396",
            RightHit    = "rbxassetid://14319054515",
            MiddleHit   = "rbxassetid://14319053883",
            LeftHit     = "rbxassetid://14319053020",

            -- ── Defense / status (real IDs) ──────────────────────────────
            BlockIdle   = "rbxassetid://14319006637",
            GuardBreak  = "rbxassetid://14319052371",
            Grip        = "rbxassetid://14351518640",
            Downed      = "rbxassetid://9994151877",
            Carried     = "rbxassetid://14351458936",

            -- ── Crouch (real IDs) ─────────────────────────────────────────
            CrouchWalk  = "rbxassetid://9196142753",
            CrouchIdle  = "rbxassetid://9196134328",
            -- Alias used in CombatService and state checks:
            Crouching   = "rbxassetid://9196134328", -- → CrouchIdle

            -- ── Knockback / ragdoll ───────────────────────────────────────
            HitReaction     = "rbxassetid://0",  -- STUB: light stagger on receive hit
            HitReactionHeavy= "rbxassetid://0",  -- STUB: heavy stagger / stumble
            KnockbackFly    = "rbxassetid://0",  -- STUB: airborne knockback tumble
            GroundSlam      = "rbxassetid://0",  -- STUB: landing impact on ground

            -- ── Execution / finisher ─────────────────────────────────────
            ExecutionCast   = "rbxassetid://0",  -- STUB: caster side of execution
            ExecutionReceive= "rbxassetid://0",  -- STUB: victim side of execution

            -- ── Misc combat ──────────────────────────────────────────────
            Parry           = "rbxassetid://0",  -- STUB: successful parry flash pose
            FeintRecovery   = "rbxassetid://0",  -- STUB: feint cancel recovery
            LungeAttack     = "rbxassetid://0",  -- STUB: generic lunge (overridden per weapon)
        },
    },

    -- ══════════════════════════════════════════════════════════════════════
    --  UI / INVENTORY
    -- ══════════════════════════════════════════════════════════════════════
    UI = {
        OpenInventory   = "rbxassetid://0", -- STUB: arm reach for bag open
        CloseInventory  = "rbxassetid://0", -- STUB: arm return from bag close
        Inspect         = "rbxassetid://0", -- STUB: item inspection hold
    },
}

return AnimationDatabase
