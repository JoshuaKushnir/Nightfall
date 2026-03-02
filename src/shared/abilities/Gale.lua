--!strict
--[[
    Gale.lua — Depth-1 Expression Ability
    Issue #126: Depth-1 Expression ability — Gale: air burst launch (caster + target)

    WIND STRIKE
    -----------
    Cast time : 0.1s
    Mana cost : 20
    Cooldown  : 6s

    Dash the caster forward up to 12 studs.  On arrival, both the caster AND any
    target within 5 studs are launched upward.  Deals 20 Posture damage to the target.
    If cast while the caster is already airborne, damage is increased to 30 and
    launch height is doubled.

    The dual-launch creates high-air engagements where both parties are airborne —
    Gale's follow-up kit specialises in aerial pressure and repositioning.

    VFX: STUB — animator implements wind-ribbon dash, upward gust column on impact,
         spiral particle ascent around both caster and target.

    Talent hooks (stubs):
        • Updraft    — while target is airborne after Wind Strike, their Breath regen is blocked
        • Gale Force — if caster was already airborne at cast, gain 1× Momentum on landing
        • Tempest Dive — follow-up ability (future depth): aerial dive into a downward slam
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- ─── Constants ────────────────────────────────────────────────────────────────

local DASH_DISTANCE        : number = 12
local CAST_TIME            : number = 0.1
local HIT_RADIUS           : number = 5    -- studs from landing
local POSTURE_DAMAGE_GROUND: number = 20
local POSTURE_DAMAGE_AIR   : number = 30   -- bonus when cast airborne
local LAUNCH_VELOCITY      : number = 60   -- studs/s upward (ground cast)
local LAUNCH_VELOCITY_AIR  : number = 120  -- studs/s upward (airborne cast)
local AIRBORNE_THRESHOLD   : number = 1.5  -- studs above ground to count as airborne

-- ─── Ability definition ──────────────────────────────────────────────────────

local Gale = {
    Id          = "WindStrike",
    Type        = "Expression",
    AspectId    = "Gale",
    Description = "Dash 12 studs and launch both you and the target upward. "
                .. "Deals 20 posture (30 if cast airborne). "
                .. "Enables aerial follow-up pressure.",

    Cooldown = 6,
    ManaCost = 20,
    CastTime = CAST_TIME,
    Range    = DASH_DISTANCE,
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
