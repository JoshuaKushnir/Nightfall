--!strict
--[[
	MovementController.lua

	Epic #56: Smooth Movement System (Deepwoken-style / Hardcore RPG)
	Sub-issues: #58 (acceleration), #57 (coyote/jump buffer), #59 (state), #60 (sprint/slope)

	Client-side controller for weighty, responsive movement:
	- Smoothed acceleration and deceleration (no instant velocity snaps)
	- Coyote time: jump shortly after leaving ledge
	- Jump buffer: jump input just before landing queues a jump
	- Sprint (hold) with optional posture awareness
	- Respects combat state (no sprint during Attacking/Blocking/Stunned)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local PlayerData = require(ReplicatedStorage.Shared.types.PlayerData)
type PlayerState = PlayerData.PlayerState

local MovementController = {}

-- Refs (set in Init)
local Player: Player? = nil
local Character: Model? = nil
local Humanoid: Humanoid? = nil
local RootPart: BasePart? = nil

-- Movement config (tunable)
local WALK_SPEED = 12
local SPRINT_SPEED = 20
local ACCELERATION = 45 -- studs/s^2 when speeding up
local DECELERATION = 55 -- studs/s^2 when slowing down
local COYOTE_TIME = 0.12 -- seconds to allow jump after leaving ground
local JUMP_BUFFER_TIME = 0.15 -- seconds to buffer jump before landing
local SPRINT_KEY = Enum.KeyCode.LeftShift

-- State
local currentSpeed = 0.0
local coyoteTimeLeft = 0.0
local jumpBufferLeft = 0.0
local lastWasOnGround = false
local lastMoveDirection: Vector3 = Vector3.zero

-- States that block sprint and use walk speed
local COMBAT_STATES: {[PlayerState]: boolean} = {
	Attacking = true,
	Blocking = true,
	Stunned = true,
	Ragdolled = true,
	Dead = true,
	Casting = true,
}

local function getStateSyncController(): any
	return MovementController._stateSyncRef
end

local function getCurrentState(): PlayerState?
	local sync = getStateSyncController()
	if sync and sync.GetCurrentState then
		return sync.GetCurrentState()
	end
	return nil
end

local function isMovementRestricted(): boolean
	local state = getCurrentState()
	if not state then return false end
	return COMBAT_STATES[state] == true
end

local function canSprint(): boolean
	if isMovementRestricted() then
		return false
	end
	return true
end

local function isOnGround(h: Humanoid): boolean
	return h.FloorMaterial ~= Enum.Material.Air
end

-- Get move direction from WASD relative to camera (Roblox has no UserInputService:GetMoveDirection)
local function getMoveDirection(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	if forward.Magnitude < 0.1 then
		forward = Vector3.new(0, 0, -1)
	end
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	local move = (forward * z + right * x)
	if move.Magnitude > 0 then
		return move.Unit
	end
	return Vector3.zero
end

function MovementController:Init(dependencies: {[string]: any}?)
	print("[MovementController] Initializing...")
	Player = Players.LocalPlayer
	if not Player then
		error("[MovementController] LocalPlayer not found")
	end
	Character = Player.Character or Player.CharacterAdded:Wait()
	local hum = Character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not hum then
		error("[MovementController] Humanoid not found")
	end
	Humanoid = hum
	RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		warn("[MovementController] HumanoidRootPart not found")
	end
	MovementController._stateSyncRef = (dependencies and dependencies.StateSyncController) or nil
	print("[MovementController] Character ready")
end

function MovementController:Start()
	print("[MovementController] Starting...")
	lastWasOnGround = isOnGround(Humanoid :: Humanoid)
	currentSpeed = (Humanoid :: Humanoid).WalkSpeed

	RunService.Heartbeat:Connect(function(dt: number)
		MovementController._Update(dt)
	end)

	UserInputService.JumpRequest:Connect(function()
		MovementController._OnJumpRequest()
	end)

	print("[MovementController] Started")
end

function MovementController._Update(dt: number)
	local humanoid = Humanoid
	local rootPart = RootPart
	if not humanoid or not rootPart or not Character or humanoid.Health <= 0 then
		return
	end

	local moveDir = getMoveDirection()
	local onGround = isOnGround(humanoid)

	-- Coyote time: grant jump window after leaving ground
	if lastWasOnGround and not onGround then
		coyoteTimeLeft = COYOTE_TIME
	end
	if not onGround then
		coyoteTimeLeft = math.max(0, coyoteTimeLeft - dt)
	end
	lastWasOnGround = onGround

	-- Jump buffer: count down when on ground and consume
	if onGround then
		if jumpBufferLeft > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			jumpBufferLeft = 0
		end
	else
		jumpBufferLeft = math.max(0, jumpBufferLeft - dt)
	end

	-- Target speed from input and sprint
	local wantsSprint = canSprint() and UserInputService:IsKeyDown(SPRINT_KEY) and moveDir.Magnitude > 0.5
	local targetSpeed = 0
	if moveDir.Magnitude > 0.5 then
		targetSpeed = wantsSprint and SPRINT_SPEED or WALK_SPEED
		lastMoveDirection = moveDir.Unit
	else
		lastMoveDirection = Vector3.zero
	end

	-- Smooth acceleration/deceleration
	local accel = (targetSpeed > currentSpeed) and ACCELERATION or DECELERATION
	currentSpeed = currentSpeed + math.clamp(targetSpeed - currentSpeed, -accel * dt, accel * dt)
	if currentSpeed < 0.5 then
		currentSpeed = 0
	end

	humanoid.WalkSpeed = currentSpeed
end

function MovementController._OnJumpRequest()
	local humanoid = Humanoid
	if not humanoid then return end

	local onGround = isOnGround(humanoid)
	if onGround then
		-- Normal jump
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	else
		-- Buffer jump for when we land
		if coyoteTimeLeft > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			coyoteTimeLeft = 0
		else
			jumpBufferLeft = JUMP_BUFFER_TIME
		end
	end
end

function MovementController:OnCharacterAdded(newCharacter: Model)
	Character = newCharacter
	local hum = newCharacter:WaitForChild("Humanoid", 5) :: Humanoid?
	Humanoid = hum or nil
	RootPart = newCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	lastWasOnGround = false
	coyoteTimeLeft = 0
	jumpBufferLeft = 0
	if Humanoid then
		currentSpeed = Humanoid.WalkSpeed
	end
	print("[MovementController] Character reset")
end

--[[
	Get the last recorded move direction (world-space, camera-relative).
	Returns Vector3.zero if not moving.
]]
function MovementController:GetLastMoveDirection(): Vector3
	return lastMoveDirection
end

return MovementController
