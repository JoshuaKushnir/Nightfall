--!strict
--[[
    Ember.lua — Depth-1 Expression Ability
    Issue #125: Depth-1 Expression ability — Ember: charging strike, damage scales with run distance

    IGNITE
    ------
    Cast time : 0.05s (near-instant)
    Mana cost : 20
    Cooldown  : 5s

    Dash the caster forward 8 studs and apply one Heat stack to any target within
    5 studs of the landing zone.  One Heat stack deals 15 Posture damage and sets
    a "Burning" status on the target (light HP drain, posture recovery halved).
    At 2× Momentum (character attribute ≥ 2), the dash applies two stacks instead.

    The Heat stack system is the foundation of Ember's combo engine.  Future
    Depth-2+ moves interact with stack count (e.g., Scorch at 3 stacks → Break).

    VFX: STUB — animator implements ember-trail dash, fiery impact ring on landing,
         glowing heat shimmer on Burned targets.

    Talent hooks (stubs):
        • Heat Transfer    — Burning targets spread 1 Heat stack to adjacent enemies
        • Torch            — Momentum bonus triggers at 1.5× instead of 2×
        • Ignition Chain   — Airborne targets hit take +1 extra stack
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- ─── Constants ────────────────────────────────────────────────────────────────

local DASH_DISTANCE    : number = 8
local CAST_TIME        : number = 0.05
local HIT_RADIUS       : number = 5    -- studs from landing to detect targets
local POSTURE_PER_HEAT : number = 15   -- posture damage per Heat stack
local BURNING_DURATION : number = 4    -- seconds Burning status lasts
local BURNING_HP_TICK  : number = 2    -- HP drained per second while Burning
local MOMENTUM_THRESHOLD: number = 2   -- ×Momentum required for double stack

-- ─── Ability definition ──────────────────────────────────────────────────────

local Ember = {
    Id          = "Ignite",
    Type        = "Expression",
    AspectId    = "Ember",
    Description = "Dash 8 studs and apply Heat (15 posture). "
                .. "At 2× Momentum, apply 2 Heat stacks. "
                .. "Burning targets lose HP over time and recover posture slower.",

    Cooldown = 5,
    ManaCost = 20,
    CastTime = CAST_TIME,
    Range    = DASH_DISTANCE,
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
