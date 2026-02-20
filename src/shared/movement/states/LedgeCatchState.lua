--!strict
--[[
Class: LedgeCatchState
Description: Owns all ledge-catch state and physics. Replaces the monolithic TryLedgeCatch body.

When the player falls at sufficient speed near a ledge edge (detected by a downward probe
slightly above and ahead), LedgeCatch:
  1. Snaps the character to a hanging position.
  2. Holds for HangDuration (PlatformStand).
  3. Auto-triggers a smooth pull-up tween to stand on the ledge.
  4. Releases to normal movement and fires ChainAction().

Private state:
  - _isLedgeCatching -- mirrors Blackboard.IsLedgeCatching.

Public surface:
  TryStart(ctx)     -- called every frame from MovementController when airborne & not restricted.
  CanCatch(ctx)     -- returns (bool, probe) for use by ClimbState.
  PullUp(ctx)       -- triggered by Space press while hanging.
  Update(dt, ctx)   -- empty; ledge logic runs fully inside TryStart/PullUp.
  Exit(ctx)         -- forced exit (restores PlatformStand).

Dependencies: MovementConfig, RunService, workspace
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- Config constants
local FORWARD_DIST  = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.ForwardDetectDistance) or 2.0
local HEIGHT_OFFSET = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.HeightCheckOffset)     or 2.5
local HANG_DURATION = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.HangDuration)          or 0.6
local PULL_DURATION = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.PullUpDuration)        or 0.4
local TRIGGER_SPEED = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.TriggerFallSpeed)      or -8
local REACH_WINDOW  = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.ReachWindow)           or 2.5

-- Module-private state
local _isLedgeCatching: boolean = false
local _currentLedgeY: number = 0
local _catchTime: number = 0

-- Public API
local LedgeCatchState = {}

-- Probe for a ledge edge above and ahead of the character.
-- Returns { hit, lookDir, ledgeY } or nil.
local function _probeLedge(ctx: any)
local humanoid = ctx.Humanoid
local rootPart = ctx.RootPart
if not humanoid or not rootPart or not ctx.Character then return nil end

local params = RaycastParams.new()
params.FilterDescendantsInstances = { ctx.Character }
params.FilterType = Enum.RaycastFilterType.Exclude

local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
if lookDir.Magnitude < 0.01 then return nil end
lookDir = lookDir.Unit

local probeOrigin = rootPart.Position + lookDir * FORWARD_DIST + Vector3.new(0, HEIGHT_OFFSET + 0.5, 0)
local hitDown = workspace:Raycast(probeOrigin, Vector3.new(0, -(HEIGHT_OFFSET + 2), 0), params)
if not hitDown then return nil end

local ledgeY = hitDown.Position.Y
local charTopY = rootPart.Position.Y + 1.5
-- Allow catching if ledge is slightly below charTopY (e.g. they climbed up to it)
if ledgeY < charTopY - 2.0 or ledgeY > charTopY + REACH_WINDOW then return nil end

return { hit = hitDown, lookDir = lookDir, ledgeY = ledgeY }
end

--[[
TryStart: snap the character to a hanging position on the detected ledge.
Guards: not already catching, airborne, not in a conflicting state.
]]
function LedgeCatchState.TryStart(ctx: any)
local humanoid = ctx.Humanoid
local rootPart = ctx.RootPart
if not humanoid or not rootPart or not ctx.Character then return end
if _isLedgeCatching then return end
if ctx.OnGround then return end
if ctx.Blackboard.IsVaulting or ctx.Blackboard.IsWallRunning or ctx.Blackboard.IsSliding then return end

local probe = _probeLedge(ctx)
if not probe then return end

-- Catch!
_isLedgeCatching = true
ctx.Blackboard.IsLedgeCatching = true
_currentLedgeY = probe.ledgeY
_catchTime = tick()
print("[LedgeCatchState] Ledge catch triggered")

humanoid.PlatformStand = true
rootPart.Anchored = true

local params = RaycastParams.new()
params.FilterDescendantsInstances = { ctx.Character }
params.FilterType = Enum.RaycastFilterType.Exclude

local hangY = probe.ledgeY - 2.8
local wallRayOrigin = Vector3.new(probe.hit.Position.X, hangY, probe.hit.Position.Z) - probe.lookDir * 5
local wallHit = workspace:Raycast(wallRayOrigin, probe.lookDir * 10, params)
local catchPos: Vector3
if wallHit then
-- Offset 1.5 studs from wall to prevent clipping
catchPos = wallHit.Position + wallHit.Normal * 1.5
catchPos = Vector3.new(catchPos.X, hangY, catchPos.Z)
else
-- Fallback if wall raycast fails (e.g. thin platform)
catchPos = Vector3.new(
rootPart.Position.X + probe.lookDir.X * 0.5,
hangY,
rootPart.Position.Z + probe.lookDir.Z * 0.5
)
end

rootPart.CFrame = CFrame.new(catchPos, catchPos + probe.lookDir)
rootPart.AssemblyLinearVelocity = Vector3.zero

-- Disable AutoRotate to prevent shift lock / camera from pivoting the character
humanoid.AutoRotate = false
-- Force Physics state to prevent Humanoid from fighting the hang
humanoid:ChangeState(Enum.HumanoidStateType.Physics)

-- Safety fallback: auto-release after 30 seconds to prevent permanent hang.
task.delay(30, function()
if _isLedgeCatching then
if humanoid then
humanoid.PlatformStand = false
humanoid.AutoRotate = true
end
if rootPart then rootPart.Anchored = false end
_isLedgeCatching = false
ctx.Blackboard.IsLedgeCatching = false
print("[LedgeCatchState] Safety timeout (30s) - released")
end
end)
end

--[[
CanCatch: returns (boolean, probe) so callers (ClimbState, MovementController)
can check feasibility without committing to the catch.
]]
function LedgeCatchState.CanCatch(ctx: any): (boolean, any)
local probe = _probeLedge(ctx)
if not probe then return false, nil end
return true, probe
end

--[[
PullUp: smoothly tween the character from the hang position onto the ledge.
Called by MovementController._OnJumpRequest while _isLedgeCatching is true.
]]
function LedgeCatchState.PullUp(ctx: any)
local humanoid = ctx.Humanoid
local rootPart = ctx.RootPart
if not humanoid or not rootPart or not _isLedgeCatching then return end

-- Prevent immediate pull-up if the player just started hanging
if tick() - _catchTime < 0.4 then return end

local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
if lookDir.Magnitude < 0.01 then lookDir = Vector3.new(0, 0, 1) end
lookDir = lookDir.Unit

local pullTarget = Vector3.new(
rootPart.Position.X + lookDir.X * 1.5,
_currentLedgeY + (humanoid.HipHeight or 2.0) + 0.5,
rootPart.Position.Z + lookDir.Z * 1.5
)

local pullStart = rootPart.Position
local startTime = tick()
local conn: RBXScriptConnection

ctx.Blackboard.IsPullingUp = true

conn = RunService.Heartbeat:Connect(function()
local t = math.min(1.0, (tick() - startTime) / PULL_DURATION)
if rootPart then
rootPart.CFrame = CFrame.new(
pullStart:Lerp(pullTarget, t),
pullTarget + lookDir
)
end
if t < 1.0 then return end
conn:Disconnect()

-- Wait a frame before restoring state
RunService.Heartbeat:Wait()
if humanoid then
humanoid.PlatformStand = false
humanoid.AutoRotate = true
end
if rootPart then rootPart.Anchored = false end
_isLedgeCatching = false
ctx.Blackboard.IsLedgeCatching = false
ctx.Blackboard.IsPullingUp = false
ctx.ChainAction()
print("[LedgeCatchState] Pull-up complete (manual)")
end)
end

function LedgeCatchState.Update(_dt: number, _ctx: any)
-- Hang and pull-up logic runs in PullUp / safety timeout task.
end

function LedgeCatchState.Enter(_ctx: any) end

function LedgeCatchState.Exit(ctx: any)
if _isLedgeCatching then
if ctx.Humanoid then
ctx.Humanoid.PlatformStand = false
ctx.Humanoid.AutoRotate = true
end
if ctx.RootPart then
ctx.RootPart.Anchored = false
end
_isLedgeCatching = false
ctx.Blackboard.IsLedgeCatching = false
print("[LedgeCatchState] Forcibly exited")
end
end

function LedgeCatchState.IsLedgeCatching(): boolean
return _isLedgeCatching
end

return LedgeCatchState