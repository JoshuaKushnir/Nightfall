--!strict
--[[
    Void.lua — Depth-1 Expression Ability
    Issue #127: Depth-1 Expression ability — Void: blink behind target + posture bonus

    BLINK
    -----
    Cast time : instant (0s)
    Mana cost : 20
    Cooldown  : 4s

    Teleports the caster up to 10 studs through geometry.  If a valid enemy target
    is within 10 studs, the caster blinks BEHIND the target (within 2 studs).
    On arrival:
        • Interrupts the target's Posture recovery for 1 second (PostureService flag)
        • Grants the caster a "VoidPostureBonus" charge for their NEXT melee strike:
          that hit deals +20 additional Posture damage.

    No cast time makes Blink a true gap-closer that's hard to react to.  Its power
    comes from chaining immediately into a melee follow-up.

    VFX: STUB — animator: void-ripple dissolve at origin, re-materialise at destination,
         dark particle burst at arrival.

    Talent hooks (stubs):
        • Nullpoint     — if target is currently Staggered, Blink also silences one
                          random ability for 1.5s
        • Phase Residue — for 0.5s after Blink the caster is Dampened-immune
                          (Momentum can't be reduced below 1×)
        • Void Slip     — if cast while airborne, destination is directly above the
                          target (+3 studs Y), enabling aerial follow-up
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- ─── Constants ────────────────────────────────────────────────────────────────

local BLINK_DISTANCE          : number = 10  -- max studs teleport
local TARGET_SEEK_RADIUS      : number = 10  -- studs to look for a target for behind-blink
local BEHIND_OFFSET           : number = 2   -- studs behind target
local POSTURE_RECOVERY_BLOCK  : number = 1   -- seconds to suppress target's posture regen
local VOID_POSTURE_BONUS      : number = 20  -- extra posture on next melee (caster buff)
local VOID_BONUS_WINDOW       : number = 8   -- seconds the bonus charge lasts

-- ─── Ability definition ──────────────────────────────────────────────────────

local Void = {
    Id          = "Blink",
    Type        = "Expression",
    AspectId    = "Void",
    Description = "Instantly teleport up to 10 studs (behind a target if in range). "
                .. "Interrupts target posture recovery for 1s. "
                .. "Next melee gains +20 posture damage.",

    Cooldown = 4,
    ManaCost = 20,
    CastTime = 0,     -- instant
    Range    = BLINK_DISTANCE,
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
