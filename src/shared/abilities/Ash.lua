--!strict
--[[
    Ash.lua — Depth-1 Expression Ability
    Issue #123: Depth-1 Expression ability — Ash: forward dash strike with decoy afterimage

    ASHEN STEP
    ----------
    Cast time : 0.15s
    Mana cost : 20
    Cooldown  : 5s

    Dash forward up to 12 studs, leaving a static afterimage Part at the origin.
    On arrival deals 15 Posture damage to any target within 5 studs.
    The afterimage persists for 4 seconds; if an enemy attacks and touches it, they
    receive a 0.3-second BlindFlash screen effect.

    Status conditions applied:
        • Posture damage (15 pts) on arrival — read by PostureService via character attribute
        • BlindFlash (0.3s) on afterimage interaction

    VFX: STUB — animator implements particle trail on dash + ash-cloud materialise/dissolve
         for the afterimage.

    Talent hooks (stubs — full logic deferred until Talent system exists):
        • Hollow Echo  — if afterimage is struck while attacker is Staggered, blind doubles
        • Momentum Trace — if cast at ≥2× Momentum, afterimage mimics last sprint direction
        • Haunting Step  — if cast airborne, afterimage spawns in air and falls slowly
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy-required server-only dependencies (safe: OnActivate is only called server-side)
local function _getNetworkProvider()
    return require(ReplicatedStorage.Shared.network.NetworkProvider)
end

-- ─── Constants ────────────────────────────────────────────────────────────────

local DASH_DISTANCE     : number = 12   -- studs forward
local CAST_TIME         : number = 0.15 -- seconds before dash lands
local POSTURE_DAMAGE    : number = 15   -- on-arrival posture
local POSTURE_RADIUS    : number = 5    -- studs around landing to hit
local AFTERIMAGE_LIFE   : number = 4    -- seconds afterimage persists
local BLIND_DURATION    : number = 0.3  -- seconds of BlindFlash effect

-- ─── Ability definition ──────────────────────────────────────────────────────

local Ash = {
    Id          = "AshenStep",
    Type        = "Expression",
    AspectId    = "Ash",
    Description = "Dash 12 studs and leave a decoy afterimage. Arrival deals 15 posture. "
                .. "Afterimage blind-flashes anyone who strikes it.",

    Cooldown  = 5,              -- seconds; enforced by AbilitySystem
    ManaCost  = 20,             -- deducted by AspectService / AbilitySystem
    CastTime  = CAST_TIME,
    Range     = DASH_DISTANCE,
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
