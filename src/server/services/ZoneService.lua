--!strict
--[[
    Class: ZoneService
    Description: Determines which Ring (0–5) a player occupies and notifies
                 ProgressionService and the owning client when the ring changes.
                 Ring boundaries are defined by BaseParts placed in the workspace
                 by the studio team (names: ZoneTrigger_Ring1 … ZoneTrigger_Ring5).
                 If no zone parts exist yet, every player defaults to Ring 0 — a
                 safe fallback that requires zero world content to compile and run.

    Issue #142: Zone trigger system — Ring boundary detection fires
                ProgressionService.SetPlayerRing

    Public API:
        ZoneService.GetPlayerRing(player) → number   -- current cached ring (0–5)
        ZoneService.ComputeRingForPosition(pos)      -- ring number for any Vector3

    Dependencies: ProgressionService, NetworkService

    Zone Part Convention (Studio → Code auto-connect):
        workspace.ZoneTrigger_Ring1  (BasePart or Folder of BaseParts for Ring 1)
        workspace.ZoneTrigger_Ring2  ...
        ...
        workspace.ZoneTrigger_Ring5
        All zones are checked Ring5 → Ring1; the first match wins.
        Ring 0 is the implicit fallback (no part needed).

    Usage:
        ZoneService:Init(dependencies)
        ZoneService:Start()
]]

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkService: any = nil
local ProgressionService: any = nil

local ZoneService = {}
ZoneService._initialized = false

-- ─── Constants ────────────────────────────────────────────────────────────────

-- Re-check ring when a player moves more than this many studs since last check.
local MOVEMENT_THRESHOLD: number = 10

-- How often (seconds) the movement-poll loop runs.
local POLL_INTERVAL: number = 0.5

-- Rings checked from outermost to innermost so the first match wins.
local RING_PRIORITY: {number} = {5, 4, 3, 2, 1}

-- ─── State ────────────────────────────────────────────────────────────────────

-- Current ring cache.   { [UserId]: number }
local _ringCache: {[number]: number} = {}

-- Last polled root position.  { [UserId]: Vector3 }
local _lastPosition: {[number]: Vector3} = {}

-- ─── Private helpers ─────────────────────────────────────────────────────────

--[[
    _getZoneParts(ring) → {BasePart}
    Collect all BaseParts that represent the zone volume for `ring`.
    Looks for workspace.ZoneTrigger_Ring<N>:
      • If it IS a BasePart, return {it}.
      • If it IS a Folder/Model, return all BasePart descendants.
      • Otherwise return {}.
]]
local function _getZoneParts(ring: number): {BasePart}
    local name = ("ZoneTrigger_Ring%d"):format(ring)
    local node = Workspace:FindFirstChild(name)
    if not node then return {} end

    if node:IsA("BasePart") then
        return {node :: BasePart}
    end

    -- Folder or Model: gather all BasePart descendants
    local parts: {BasePart} = {}
    for _, desc in node:GetDescendants() do
        if desc:IsA("BasePart") then
            table.insert(parts, desc :: BasePart)
        end
    end
    return parts
end

--[[
    _positionInsidePart(pos, part) → boolean
    Axis-aligned bounding-box containment test in world space.
    Uses the part's CFrame so it handles rotated parts correctly.
]]
local function _positionInsidePart(pos: Vector3, part: BasePart): boolean
    -- Transform pos into the part's local frame.
    local localPos = part.CFrame:PointToObjectSpace(pos)
    local halfSize = part.Size / 2
    return math.abs(localPos.X) <= halfSize.X
        and math.abs(localPos.Y) <= halfSize.Y
        and math.abs(localPos.Z) <= halfSize.Z
end

--[[
    _computeRing(pos) → number
    Walk rings 5 → 1; return the first ring whose zone parts contain `pos`.
    Returns 0 if no ring parts exist or pos doesn't fall inside any.
]]
local function _computeRing(pos: Vector3): number
    for _, ring in RING_PRIORITY do
        local parts = _getZoneParts(ring)
        for _, part in parts do
            if _positionInsidePart(pos, part) then
                return ring
            end
        end
    end
    return 0
end

--[[
    _updatePlayerRing(player, pos)
    Re-compute the ring for `pos`; if it differs from the cached ring,
    update the cache, notify ProgressionService, and fire RingChanged to client.
]]
local function _updatePlayerRing(player: Player, pos: Vector3)
    local uid = player.UserId
    local newRing = _computeRing(pos)
    local oldRing = _ringCache[uid] or 0

    if newRing == oldRing then return end

    _ringCache[uid] = newRing

    -- verbose logging for QA
    print(('[ZoneService] %s changed ring %d → %d'):format(player.Name, oldRing, newRing))

    -- Notify progression layer (already exists on ProgressionService per NF-042/038)
    if ProgressionService and ProgressionService.SetPlayerRing then
        local ok, err = pcall(ProgressionService.SetPlayerRing, ProgressionService, player, newRing)
        if not ok then
            warn(("[ZoneService] ProgressionService.SetPlayerRing error: %s"):format(tostring(err)))
        end
    end

    -- Fire event to the owning client so UI can react (HUD ring indicator, etc.)
    if NetworkService and NetworkService.SendToClient then
        local ok, err = pcall(NetworkService.SendToClient, NetworkService, player, "RingChanged", {
            OldRing = oldRing,
            NewRing = newRing,
        })
        if not ok then
            warn(("[ZoneService] RingChanged fire error: %s"):format(tostring(err)))
        end
    end

    print(("[ZoneService] %s → Ring %d (was %d)"):format(player.Name, newRing, oldRing))
end

--[[
    _pollPlayer(player)
    Called every POLL_INTERVAL.  Checks movement threshold; skips the zone test
    unless the player has moved enough studs since the last check.
]]
local function _pollPlayer(player: Player)
    local char = player.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local uid = player.UserId
    local pos = root.Position
    local last = _lastPosition[uid]

    if last and (pos - last).Magnitude < MOVEMENT_THRESHOLD then return end

    _lastPosition[uid] = pos
    _updatePlayerRing(player, pos)
end

-- ─── Player lifecycle ─────────────────────────────────────────────────────────

local function _onPlayerAdded(player: Player)
    local uid = player.UserId
    _ringCache[uid] = 0
    _lastPosition[uid] = Vector3.zero

    -- Also force-check as soon as the character spawns.
    player.CharacterAdded:Connect(function(_char)
        task.wait(0.5)  -- brief settle for HumanoidRootPart to exist
        _pollPlayer(player)
    end)
end

local function _onPlayerRemoving(player: Player)
    local uid = player.UserId
    _ringCache[uid] = nil
    _lastPosition[uid] = nil
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
    GetPlayerRing(player) → number
    Returns the cached ring index (0–5) for the given player.
    Returns 0 if the player hasn't been polled yet.
]]
function ZoneService.GetPlayerRing(player: Player): number
    return _ringCache[player.UserId] or 0
end

--[[
    ComputeRingForPosition(pos) → number
    Stateless helper — computes the ring for any world position on demand.
    Used by HollowedService to decide spawn ring, by tests, and by tools.
]]
function ZoneService.ComputeRingForPosition(pos: Vector3): number
    return _computeRing(pos)
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function ZoneService:Init(dependencies: {[string]: any})
    NetworkService    = dependencies.NetworkService    or NetworkService
    ProgressionService = dependencies.ProgressionService or ProgressionService

    -- Fallback: lazy-require if not injected (supports standalone tests)
    if not NetworkService then
        local ok, svc = pcall(require, script.Parent.NetworkService)
        if ok then NetworkService = svc end
    end
    if not ProgressionService then
        local ok, svc = pcall(require, script.Parent.ProgressionService)
        if ok then ProgressionService = svc end
    end

    self._initialized = true
    print("[ZoneService] Initialized")
end

function ZoneService:Start()
    assert(self._initialized, "[ZoneService] Must call Init() before Start()")

    -- Hook existing players (server-start race)
    for _, player in Players:GetPlayers() do
        _onPlayerAdded(player)
    end

    Players.PlayerAdded:Connect(_onPlayerAdded)
    Players.PlayerRemoving:Connect(_onPlayerRemoving)

    -- Poll loop: light-weight heartbeat that only fires zone checks when the
    -- player has moved enough.  Accumulates dt instead of spawning per-frame.
    local _accumulator = 0
    RunService.Heartbeat:Connect(function(dt: number)
        _accumulator += dt
        if _accumulator < POLL_INTERVAL then return end
        _accumulator = 0

        for _, player in Players:GetPlayers() do
            local ok, err = pcall(_pollPlayer, player)
            if not ok then
                warn(("[ZoneService] Poll error for %s: %s"):format(player.Name, tostring(err)))
            end
        end
    end)

    print("[ZoneService] Started — zone poll interval: " .. POLL_INTERVAL .. "s")
end

return ZoneService
