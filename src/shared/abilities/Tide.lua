--!strict
--[[
    Tide.lua — Depth-1 Expression Ability
    Issue #124: Depth-1 Expression ability — Tide: water surge push + slow

    CURRENT
    -------
    Cast time : 0.1s
    Mana cost : 20
    Cooldown  : 7s

    Projects a water surge up to 15 studs in the cast direction.  Any player hit
    within a 5-stud radius of the surge tip is:
        • Knocked back 8 studs away from the caster
        • Dealt 25 Posture damage
        • If they hit terrain within 1 second of the knockback → additional 20 HP damage
          and gain Grounded status for 1.5 seconds

    VFX: STUB — animator implements water-ribbon projectile, foam splash on terrain hit

    Talent hooks (stubs — deferred until Talent system exists):
        • Riptide          — if target is airborne at hit, double knockback distance
        • Saturating Wave  — applies Saturated status (interacts with Ember cross-Aspect)
        • Drowning Shore   — halves target Breath regen for 3s
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- ─── Constants ────────────────────────────────────────────────────────────────

local SURGE_RANGE       : number = 15  -- max studs forward
local SURGE_RADIUS      : number = 5   -- sphere radius for hit detection at tip
local KNOCKBACK_DIST    : number = 8   -- studs target is pushed
local POSTURE_DAMAGE    : number = 25  -- pts
local TERRAIN_HP_BONUS  : number = 20  -- HP damage if target hits terrain
local GROUNDED_DURATION : number = 1.5 -- seconds of Grounded status
local CAST_TIME         : number = 0.1 -- seconds before surge is emitted

-- ─── Ability definition ──────────────────────────────────────────────────────

local Tide = {
    Id          = "Current",
    Type        = "Expression",
    AspectId    = "Tide",
    Description = "Launch a water surge up to 15 studs. Targets hit are knocked back, "
                .. "take 25 posture, and may be Grounded if they hit terrain.",

    Cooldown = 7,
    ManaCost = 20,
    CastTime = CAST_TIME,
    Range    = SURGE_RANGE,
}

-- ─── VFX stubs ───────────────────────────────────────────────────────────────

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
