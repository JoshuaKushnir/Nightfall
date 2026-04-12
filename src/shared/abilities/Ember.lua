
-- Service caching to avoid per-hit require overhead (Optimization #189)
local _services = {}
local function GetService(name)
	if _services[name] ~= nil then return _services[name] end
	local RunService = game:GetService("RunService")

	if name == "NetworkProvider" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
	elseif name == "HitboxService" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.modules.combat.HitboxService)
	elseif name == "PostureService" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.PostureService)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "CombatService" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.CombatService)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "TickManager" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.TickManager)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end

	elseif name == "DummyService" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.DummyService)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	end

	return _services[name]
end
--!strict
--[[
    Class: Ember
    Description: EMBER â€” Stack-based escalation, aggressive commitment.
                 Full attunement moveset: 5 abilities, 3 talent stubs each.
                 Identity: Highest ceiling for sustained damage. Heat stacks on the
                 opponent and Momentum working together create compounding pressure.
    Issue: #149 â€” refactor Aspect system to full moveset
    Dependencies: none (server-only via OnActivate)

    Move list:
        [1] Ignite      (UtilityProc) â€” Stack builder / initiator
        [2] Flashfire   (Offensive)   â€” AoE stack detonation / payoff
        [3] HeatShield  (Defensive)   â€” Absorb hits â†’ generate stacks
        [4] Surge       (SelfBuff)    â€” Momentum amplifier / aggression burst
        [5] CinderField (UtilityProc) â€” Area control / sustained stack pressure
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- HEAT STACK SYSTEM CONSTANTS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local HEAT_STACK_MAX         : number = 3
local HEAT_STACK_DECAY_TIME  : number = 6    -- seconds before stacks expire
local BURNING_HP_PER_SEC     : number = 5    -- HP drain while Burning
local BURNING_DURATION       : number = 4    -- seconds of Burning at max stacks

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 1 â€” IGNITE  (UtilityProc)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local IGNITE_DASH_DIST      : number = 8
local IGNITE_POSTURE_PER_HEAT: number = 15
local IGNITE_HIT_RADIUS     : number = 4
local IGNITE_HP_DMG         : number = 5   -- HP per stack on contact (placeholder)

-- VFX STUB â€” animator: ember-trail dash + ground-ring burst at landing
local function _VFX_Ignite_Dash(_origin: Vector3, _dest: Vector3) end
local function _VFX_Ignite_Impact(_pos: Vector3, _stacks: number) end
-- VFX STUB â€” animator: persistent flame shimmer on character while Burning
local function _VFX_BurningStatus(_char: Model) end

local function _applyHeatStack(
    tPlayer: Player?,   -- nil if dummy
    dummyId: string?,   -- nil if player
    char: Model,
    stacks: number,
    casterPos: Vector3
)
    local currentStacks = (char:GetAttribute("HeatStacks") :: number?) or 0
    local newStacks = math.min(HEAT_STACK_MAX, currentStacks + stacks)
    char:SetAttribute("HeatStacks", newStacks)

    -- Posture gain (pressure fills on hit) â€” players only, dummies have no posture
    if tPlayer then
        local ok, PS = pcall(function()
            return GetService("PostureService")
        end)
        if ok and PS then
            PS.GainPosture(tPlayer, IGNITE_POSTURE_PER_HEAT * stacks)
        end
    end

    -- HP damage
    local ok2, CS = pcall(function()
        return GetService("CombatService")
    end)
    if tPlayer then
        if ok2 and CS then
            CS.ApplyBreakDamage(tPlayer, IGNITE_HP_DMG * stacks)
        end
    elseif dummyId then
        local ok3, DS = pcall(function()
            return GetService("DummyService")
        end)
        if ok3 and DS then
            DS.ApplyDamage(dummyId, IGNITE_HP_DMG * stacks, casterPos)
        end
    end

    -- Burning at max stacks
    if newStacks >= HEAT_STACK_MAX then
        char:SetAttribute("StatusBurning", true)
        char:SetAttribute("BurningExpiry", tick() + BURNING_DURATION)
        _VFX_BurningStatus(char)

        local TM = GetService("TickManager")
        if TM then
            local effectId = "Burning_" .. tostring(char:GetDebugId())
            TM.RegisterEffect(effectId, 1, function()
                if not char or not char.Parent then
                    TM.DeregisterEffect(effectId)
                    return
                end
                local expiry = char:GetAttribute("BurningExpiry") :: number?
                if not expiry or tick() >= expiry then
                    char:SetAttribute("StatusBurning", nil)
                    char:SetAttribute("BurningExpiry", nil)
                    TM.DeregisterEffect(effectId)
                    return
                end

                if tPlayer then
                    if ok2 and CS then CS.ApplyBreakDamage(tPlayer, BURNING_HP_PER_SEC) end
                elseif dummyId then
                    local ok3, DS = pcall(function() return GetService("DummyService") end)
                    if ok3 and DS then DS.ApplyDamage(dummyId, BURNING_HP_PER_SEC, nil) end
                end
            end)
        end
    end

    print(("[Ignite] %s â† %d stack(s) â†’ %d total (+%dHP)"):format(
        tPlayer and tPlayer.Name or tostring(dummyId),
        stacks, newStacks, IGNITE_HP_DMG * stacks))
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 2 â€” FLASHFIRE  (Offensive)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.15s cast. 5-stud sphere burst. 20 posture to all targets. Consumes all
--  Heat stacks: +8 HP per stack. Overheat (2s): mana regen paused, melee +20%.

local FLASHFIRE_RADIUS       : number = 4
local FLASHFIRE_POSTURE_DMG  : number = 20
local FLASHFIRE_HP_PER_STACK : number = 8
local FLASHFIRE_OVERHEAT_DUR : number = 2

-- VFX STUB â€” animator: radial orange-white heat burst, scorched ground ring
local function _VFX_Flashfire(_pos: Vector3, _stacks: number) end
-- VFX STUB â€” animator: heat shimmer aura around caster during Overheat
local function _VFX_Overheat_Enter(_caster: Player) end
local function _VFX_Overheat_Exit(_caster: Player) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 3 â€” HEAT SHIELD  (Defensive)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.1s cast. 1.5s: convert incoming HP damage â†’ Posture at 150% rate.
--  On expiry: restore 1 stack per hit absorbed (max 3 stacks to caster).

local HEAT_SHIELD_DURATION      : number = 1.5
local HEAT_SHIELD_POSTURE_MULT  : number = 1.5
local HEAT_SHIELD_STACK_MAX     : number = 3

-- VFX STUB â€” animator: ember/red energy field around caster, crinkles on each absorbed hit
local function _VFX_HeatShield_Enter(_caster: Player) end
local function _VFX_HeatShield_Exit(_caster: Player) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 4 â€” SURGE  (SelfBuff)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.25s cast. +1 Momentum stack immediately. 4s sprint speed boost (+3 studs/s).
--  First melee hit within window applies 1 Heat stack automatically.
--  Speed boost cancelled on taking damage.

local SURGE_DURATION        : number = 4
local SURGE_SPEED_BONUS     : number = 3  -- studs/s

-- VFX STUB â€” animator: ember aura around legs during sprint boost, fades on damage
local function _VFX_Surge_Enter(_caster: Player) end
local function _VFX_Surge_Exit(_caster: Player) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVE 5 â€” CINDER FIELD  (UtilityProc)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  0.3s cast. 6-stud radius ember field around caster for 6s. Targets inside:
--  4 HP/s drain + 1 Heat stack per 2s. Field does not follow caster.

local CINDER_FIELD_RADIUS   : number = 5
local CINDER_FIELD_DURATION : number = 6
local CINDER_FIELD_HP_PER_S : number = 4
local CINDER_FIELD_STACK_INTERVAL: number = 2  -- seconds between stack applications

-- VFX STUB â€” animator: ground-level ember glow zone, constantly flickering embers rising
local function _VFX_CinderField_Create(_pos: Vector3, _radius: number) end
local function _VFX_CinderField_Expire(_pos: Vector3) end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MOVESET MODULE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local Ember = {
    AspectId    = "Ember",
    DisplayName = "Ember",
    Moves = {} :: any,
}

-- â”€â”€ Move 1 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Ember.Moves[1] = {
    Id          = "Ignite",
    Name        = "Ignite",
    AspectId    = "Ember",
    Slot        = 1,
    Type        = "Expression",
    MoveType    = "UtilityProc",
    Description = "Charge forward 8 studs. On contact: 1 Heat stack + 15 posture damage. "
                .. "At 3 stacks: Burning (5 HP/s for 4s, Posture recovery halved). "
                .. "At 2Ã— Momentum: apply 2 stacks instead. Shortest cooldown in kit.",

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
            OnActivate    = nil, -- STUB â€” requires Burning check at hit time
        },
        {
            Id            = "Torch",
            Name          = "Torch",
            InteractsWith = "Momentum",
            Description   = "At 2Ã— Momentum, Ignite applies 2 Heat stacks instead of 1. "
                          .. "Movement investment rewarded with double stack pressure.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Momentum threshold check
        },
        {
            Id            = "IgnitionChain",
            Name          = "Ignition Chain",
            InteractsWith = "Airborne",
            Description   = "If Ignite connects mid-air (both airborne), neither takes knockback "
                          .. "from the collision â€” both continue moving. Aerial combo-extender.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires airborne detection for both players
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

        -- Determine stack count (Torch talent: 2Ã— Momentum â†’ 2 stacks)
        local momentum     = (root:GetAttribute("Momentum") :: number?) or 1
        local stacksToApply = 1
        -- TALENT HOOK STUB: Torch â€” at 2Ã— Momentum apply 2 stacks
        if momentum >= 2 then
            -- Base behavior without talent: still 1 stack; talent changes this to 2
            -- stacksToApply = 2  â† enabled when talent is purchased
        end

        task.delay(0.2, function()
            if not char or not char.Parent then return end
            if not root or not root.Parent then return end
            root.CFrame = CFrame.new(destination, destination + forward)
            _VFX_Ignite_Dash(origin, destination)

            -- Use HitboxService for landing detection
            local HitboxService = GetService("HitboxService")
            pcall(function()
                local PostureService = GetService("PostureService")

                HitboxService.CreateHitbox({
                    Shape = "Sphere",
                    Owner = player,
                    Position = destination,
                    Size = Vector3.new(IGNITE_HIT_RADIUS, IGNITE_HIT_RADIUS, IGNITE_HIT_RADIUS),
                    Damage = 0,
                    LifeTime = 0.15,
                    OnHit = function(hitTarget: any)
                        local tPlayer: Player? = nil
                        local dummyId: string? = nil

                        if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                            tPlayer = hitTarget :: Player
                        elseif type(hitTarget) == "string" then
                            dummyId = hitTarget
                        else
                            return  -- unknown target type, ignore
                        end

                        -- Resolve character model for heat stacks
                        local tChar: Model? = nil
                        if tPlayer then
                            tChar = tPlayer.Character
                        else
                            local ok, DS = pcall(function()
                                return GetService("DummyService")
                            end)
                            if ok and DS and dummyId then
                                tChar = DS.GetDummyModel(dummyId)
                            end
                        end
                        if not tChar then return end

                        _applyHeatStack(tPlayer, dummyId, tChar, stacksToApply, destination)
                    end
                })
            end)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = GetService("NetworkProvider")
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Ignite", TargetPosition = targetPosition }) end
    end,
}

-- â”€â”€ Move 2 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            Description   = "At 3Ã— Momentum, Flashfire radius increases to 8 studs and Overheat "
                          .. "extends to 3.5s. Highest-risk version â†’ highest-reward.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Momentum check + radius override
        },
        {
            Id            = "ScorchMark",
            Name          = "Scorch Mark",
            InteractsWith = "Saturated",
            Description   = "Flashfire creates a 4-stud burning ground tile for 5s. Saturated "
                          .. "targets entering gain Burning. Connects with Tide cross-interaction.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires burning zone creation
        },
        {
            Id            = "ThermalFeedback",
            Name          = "Thermal Feedback",
            InteractsWith = "Posture",
            Description   = "During Overheat, blocked hits drain an extra +10 Posture per hit "
                          .. "(normally blocked hits drain 0 HP). Makes Overheat attacks punish blocking.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires block event hook during Overheat
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
        -- TALENT HOOK STUB: Flashpoint â€” at 3Ã— Momentum, radius = 8, overheatDur = 3.5

        -- AoE hit detection
        local HitboxService = GetService("HitboxService")
        pcall(function()
            HitboxService.CreateHitbox({
                Shape = "Sphere",
                Owner = player,
                Position = origin,
                Size = Vector3.new(radius, radius, radius),
                Damage = 0,
                LifeTime = 0.15,
                OnHit = function(hitTarget: any)
                    local tChar
                    if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                        tChar = hitTarget.Character
                    elseif type(hitTarget) == "string" then
                        local DummyService = GetService("DummyService")
                        tChar = DummyService.GetDummyModel(hitTarget)
                    end
                    if not tChar then return end

                    -- Posture damage
                    tChar:SetAttribute("IncomingPostureDamage",
                        (tChar:GetAttribute("IncomingPostureDamage") or 0) + FLASHFIRE_POSTURE_DMG)
                    tChar:SetAttribute("IncomingPostureDamageSource", player.Name .. "_Flashfire")

                    -- Consume Heat stacks â†’ HP damage
                    local stacks = (tChar:GetAttribute("HeatStacks") :: number?) or 0
                    if stacks > 0 then
                        local hpDmg = stacks * FLASHFIRE_HP_PER_STACK
                        tChar:SetAttribute("IncomingHPDamage",
                            (tChar:GetAttribute("IncomingHPDamage") or 0) + hpDmg)
                        tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_FlashfireStacks")
                        tChar:SetAttribute("HeatStacks", 0)
                        tChar:SetAttribute("HeatStackExpiry", nil)
                    end
                    -- TALENT HOOK STUB: ScorchMark â€” create burning ground tile at origin
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
        local np = GetService("NetworkProvider")
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Flashfire", TargetPosition = targetPosition }) end
    end,
}

-- â”€â”€ Move 3 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Ember.Moves[3] = {
    Id          = "HeatShield",
    Name        = "Heat Shield",
    AspectId    = "Ember",
    Slot        = 3,
    Type        = "Expression",
    MoveType    = "Defensive",
    Description = "For 1.5s, convert incoming HP damage â†’ Posture at 150% rate. "
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
            OnActivate    = nil, -- STUB â€” requires 3-hit counter check + free Ignite pulse
        },
        {
            Id            = "EmberArmor",
            Name          = "Ember Armor",
            InteractsWith = "Burning (self)",
            Description   = "While Heat Shield is active, if you are Burning, the Burning HP drain "
                          .. "is paused. The defensive window also clears your own debuff timer.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Burning pause flag during shield
        },
        {
            Id            = "ThermalMass",
            Name          = "Thermal Mass",
            InteractsWith = "Airborne",
            Description   = "Heat Shield can be cast while airborne. If cast airborne, absorbed "
                          .. "hits convert to a single 4-stud burst on landing (no stack consumption).",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires airborne state + landing event hook
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

        -- TALENT HOOK STUB: EmberArmor â€” pause Burning HP drain for duration
        -- TALENT HOOK STUB: ThermalMass â€” if airborne, store hits for landing burst

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
                -- TALENT HOOK STUB: ReturnFire â€” if absorbed == 3, release free Ignite pulse
            end

            _VFX_HeatShield_Exit(player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = GetService("NetworkProvider")
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "HeatShield", TargetPosition = targetPosition }) end
    end,
}

-- â”€â”€ Move 4 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            OnActivate    = nil, -- STUB â€” requires feint â†’ Dampened hook during Surge state
        },
        {
            Id            = "Accelerant",
            Name          = "Accelerant",
            InteractsWith = "Breath",
            Description   = "Surge restores 15 Breath on activation. Enables movement burst "
                          .. "immediately â€” sprint out of a bad position into a new angle.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires Breath attribute restore on cast
        },
        {
            Id            = "BurningApproach",
            Name          = "Burning Approach",
            InteractsWith = "Burning",
            Description   = "If Surge is activated while a target within 8 studs is Burning, "
                          .. "you gain 2 Momentum stacks instead of 1. Rewards pressured targets.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires nearby Burning target detection at cast
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

        -- TALENT HOOK STUB: BurningApproach â€” if nearby Burning target, +2 stacks instead
        -- TALENT HOOK STUB: Accelerant â€” restore 15 Breath

        -- Surge active state
        char:SetAttribute("StatusSurge", true)
        char:SetAttribute("SurgeExpiry", tick() + SURGE_DURATION)
        char:SetAttribute("SurgeFirstHitReady", true)  -- CombatService reads: first hit gets free stack
        _VFX_Surge_Enter(player)

        -- TALENT HOOK STUB: SurgeFeint â€” during state, feints apply Dampened

        task.delay(SURGE_DURATION, function()
            if not char or not char.Parent then return end
            char:SetAttribute("StatusSurge", nil)
            char:SetAttribute("SurgeExpiry", nil)
            char:SetAttribute("SurgeFirstHitReady", nil)
            _VFX_Surge_Exit(player)
        end)
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = GetService("NetworkProvider")
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "Surge", TargetPosition = targetPosition }) end
    end,
}

-- â”€â”€ Move 5 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            OnActivate    = nil, -- STUB â€” requires Burning trigger hook in heat stack system
        },
        {
            Id            = "HeatSink",
            Name          = "Heat Sink",
            InteractsWith = "Overheat",
            Description   = "If Flashfire is cast while standing in your own Cinder Field, Overheat "
                          .. "duration extends from 2s to 5s. Cinder Field becomes a Flashfire amplifier.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires zone check at Flashfire cast time
        },
        {
            Id            = "Draft",
            Name          = "Draft",
            InteractsWith = "Airborne + Gale synergy",
            Description   = "Cinder Field creates an upward thermal column. You and allies in the "
                          .. "field gain slightly increased jump height. Ember/Gale cross-build interaction.",
            IsUnlocked    = false,
            OnActivate    = nil, -- STUB â€” requires jump height modifier in MovementService
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
        local HitboxService = GetService("HitboxService")
        local DummyService = GetService("DummyService") or nil

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
                    OnHit = function(hitTarget: any)
                        local tChar
                        if typeof(hitTarget) == "Instance" and hitTarget:IsA("Player") then
                            tChar = hitTarget.Character
                        elseif type(hitTarget) == "string" and DummyService then
                            tChar = DummyService.GetDummyModel(hitTarget)
                        end
                        if not tChar then return end

                        -- HP drain per tick
                        tChar:SetAttribute("IncomingHPDamage",
                            (tChar:GetAttribute("IncomingHPDamage") or 0) + CINDER_FIELD_HP_PER_S * dt)
                        tChar:SetAttribute("IncomingHPDamageSource", player.Name .. "_CinderFieldDOT")
                        -- Heat stack per interval
                        if stackTimer >= CINDER_FIELD_STACK_INTERVAL then
                            -- Resolve player vs dummy identity for the correct _applyHeatStack signature
                            local tPtr = Players:GetPlayerFromCharacter(tChar)
                            local dId: string? = if not tPtr
                                then (tChar.Name:match("^Dummy_(.+)$") :: string?)
                                else nil
                            _applyHeatStack(tPtr, dId, tChar, 1, fieldCenter)
                            -- TALENT HOOK STUB: Bonfire â€” if reached 3 stacks, apply Grounded 2s
                        end
                    end
                })
            end)

            if stackTimer >= CINDER_FIELD_STACK_INTERVAL then
                stackTimer -= CINDER_FIELD_STACK_INTERVAL
            end
            return false
        end

        local TM = GetService("TickManager")
        if TM then
            local effectId = "CinderField_" .. tostring(tick()) .. "_" .. tostring(caster.UserId)
            local start = tick()
            TM.RegisterEffect(effectId, 0.1, function()
                if tick() - start >= CINDER_FIELD_DURATION or _tick(0.1) then
                    TM.DeregisterEffect(effectId)
                    if zonePart and zonePart.Parent then
                        _VFX_CinderField_Expire(fieldCenter)
                        zonePart:Destroy()
                    end
                end
            end)
        end
    end,

    ClientActivate = function(targetPosition: Vector3?)
        local np = GetService("NetworkProvider")
        local remote = np:GetRemoteEvent("AbilityCastRequest")
        if remote then remote:FireServer({ AbilityId = "CinderField", TargetPosition = targetPosition }) end
    end,
}

-- ── Animations ──────────────────────────────────────────────────────────────
-- Primary animation source for Ember abilities. Move names match the ability
-- keys above. AnimationDatabase.Combat.Aspect.Ember is the fallback.
Ember.Animations = {
    Ignite      = "rbxassetid://0", -- STUB
    Flashfire   = "rbxassetid://0", -- STUB
    HeatShield  = "rbxassetid://0", -- STUB
    Surge       = "rbxassetid://0", -- STUB
    CinderField = "rbxassetid://0", -- STUB
}

return Ember
