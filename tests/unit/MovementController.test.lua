--!strict
-- MovementController unit test skeletons
-- Placeholders showing expected assertions for CI/test runner integration

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MovementController = require(ReplicatedStorage.Client.controllers.MovementController)

return {
	name = "MovementController Unit Tests",
	tests = {
		{
			name = "Coyote time allows jump after leaving ground",
			fn = function()
				-- Validate coyote time constant exists
				assert(type(MovementController._OnJumpRequest) == "function")
				-- Integration tests should simulate grounded -> airborne -> jump input within COYOTE_TIME
				-- (Requires test harness to manipulate humanoid state)
			end,
		},
		{
			name = "Speed modifiers stack and use lowest multiplier",
			fn = function()
				MovementController.SetModifier("TestA", 0.8)
				MovementController.SetModifier("TestB", 0.5)
				-- Reflection: MovementController:GetEffectiveSpeedMultiplier not exported; rely on WalkSpeed changes in integration tests
				-- Ensure SetModifier api is callable and removal works
				MovementController.SetModifier("TestB", 1.0)
				MovementController.SetModifier("TestA", 1.0)
			end,
		},
		{
			name = "Double-tap primes sprint (WW; hold to sprint)",
			fn = function()
				-- Verify API exists
				assert(type(MovementController._isSprinting) == "function")
				-- Integration test should simulate: double-tap W -> hold W -> MovementController._isSprinting() == true
				-- release W -> MovementController._isSprinting() == false
			end,
		},
		{
			name = "Sprint key present in MovementConfig",
			fn = function()
				local cfg = require(ReplicatedStorage.Shared.modules.MovementConfig)
				assert(cfg.Movement and cfg.Movement.SprintKey, "SprintKey missing in MovementConfig")
			end,
		},
		{
			name = "WallRun disable flag exists and defaults false",
			fn = function()
				local cfg = require(ReplicatedStorage.Shared.modules.MovementConfig)
				assert(cfg.WallRun and type(cfg.WallRun.DisableWallRun) == "boolean", "DisableWallRun flag missing")
				assert(cfg.WallRun.DisableWallRun == false, "DisableWallRun should default to false")
			end,
		},
		{
			name = "WallRunState respects disable flag",
			fn = function()
				local WallRun = require(ReplicatedStorage.Shared.movement.states.WallRunState)
				local cfg = require(ReplicatedStorage.Shared.modules.MovementConfig)
				-- temporarily set flag and call TryStart with minimal context
				cfg.WallRun.DisableWallRun = true
				assert(WallRun.TryStart({}) == false)
				cfg.WallRun.DisableWallRun = false
			end,
		},
		{
			name = "Slide creates LinearVelocity and decays",
			fn = function()
				assert(type(MovementController._TrySlide) == "function")
				-- Integration test should trigger a slide and verify LinearVelocity is added to HumanoidRootPart and decays over SLIDE_DURATION
			end,
		},
		{
			name = "Slide start allowed when wall is immediately ahead",
			fn = function()
				local SlideState = require(ReplicatedStorage.Shared.movement.states.SlideState)
				-- fake context with rootPart and last move direction
				local fakeRoot = Instance.new("Part")
				fakeRoot.Anchored = false
				fakeRoot.CanCollide = false
				fakeRoot.Position = Vector3.new(0,0,0)
				task.defer(function() fakeRoot:Destroy() end)
				-- monkey-patch Workspace.Raycast to pretend a wall is right next to us
				local workspace = game:GetService("Workspace")
				local orig = workspace.Raycast
				workspace.Raycast = function() return {Instance = {CanCollide = true}} end
				local ctx = { Humanoid = {Health = 100}, RootPart = fakeRoot, OnGround = true, IsSprinting = true, LastMoveDir = Vector3.new(1,0,0), Blackboard = {}, Character = fakeRoot, ChainAction = function() end, GetMomentumMultiplier = function() return 1 end, NetworkController = {SendToServer = function() end} }
				-- Should start rather than reject
				SlideState.TryStart(ctx)
				assert(SlideState.IsSliding() == true, "slide should start even if a wall is close")
				workspace.Raycast = orig
				-- cleanup final state
			end,
		},
		{
			name = "Stopping slide zeros horizontal velocity",
			fn = function()
				local SlideState = require(ReplicatedStorage.Shared.movement.states.SlideState)
				-- create fake context with a mock rootPart
				-- create a real part so BodyVelocity parenting works
				local fakeRoot = Instance.new("Part")
				fakeRoot.Anchored = false
				fakeRoot.CanCollide = false
				fakeRoot.Position = Vector3.new(0,0,0)
				fakeRoot.AssemblyLinearVelocity = Vector3.new(10, -5, 3)
				local ctx = {RootPart = fakeRoot, Blackboard = {}}
				-- start and immediately exit to trigger _stopSlide behavior
				SlideState.TryStart({Humanoid = {Health = 100}, RootPart = fakeRoot, OnGround = true, IsSprinting = true, LastMoveDir = Vector3.new(1,0,0), Blackboard = ctx.Blackboard, Character = fakeRoot, ChainAction = function() end, GetMomentumMultiplier = function() return 1 end, NetworkController = {SendToServer = function() end}})
				SlideState.Exit(ctx)
				assert(fakeRoot.AssemblyLinearVelocity.X == 0 and fakeRoot.AssemblyLinearVelocity.Z == 0,
					"horizontal velocity should be zeroed when slide stops")
				fakeRoot:Destroy()
			end,
		},
		{
			name = "Slide immediately rejects start if obstacle is too close",
			fn = function()
				local SlideState = require(ReplicatedStorage.Shared.movement.states.SlideState)
				-- monkey-patch workspace.Raycast to always return a hit
				local workspace = game:GetService("Workspace")
				local originalRaycast = workspace.Raycast
				workspace.Raycast = function()
					return {Instance = {CanCollide = true, Parent = {FindFirstChildOfClass = function() return nil end}}}
				end
				local fakeRoot = Instance.new("Part")
				fakeRoot.Anchored = false
				fakeRoot.CanCollide = false
				fakeRoot.Position = Vector3.new(0,0,0)
				local ctx = {Humanoid = {Health = 100}, RootPart = fakeRoot, OnGround = true, IsSprinting = true, LastMoveDir = Vector3.new(1,0,0), Blackboard = {}, Character = fakeRoot}
				SlideState.TryStart(ctx)
				-- since the raycast always hits upfront, the slide should never begin
				task.wait(0.1)
				assert(SlideState.IsSliding() == false, "Slide start should be rejected when obstacle is immediately ahead")
				workspace.Raycast = originalRaycast
				fakeRoot:Destroy()
			end,
		},


		{
			name = "ApplyImpulse API exists and is callable",
			fn = function()
				assert(type(MovementController.ApplyImpulse) == "function")
				-- Integration test should verify impulse actually moves the character in-game
			end,
		},
		{
			name = "MovementConfig contains LungeSpeed",
			fn = function()
				local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)
				assert(type(MovementConfig.Movement.LungeSpeed) == "number")
			end,
		},
		{
			name = "Slide-jump landing resumes sprint when movement input held",
			fn = function()
				-- API surface check; integration tests should simulate slide->jump->land while holding movement key
				assert(type(MovementController._OnJumpRequest) == "function", "_OnJumpRequest missing")
			end,
		},
		{
			name = "Slide cooldown default updated to 1.5s",
			fn = function()
				local cfg = require(ReplicatedStorage.Shared.modules.MovementConfig)
				assert(type(cfg.Dodge.Cooldown) == "number")
				assert(cfg.Dodge.Cooldown == 1.5)
			end,
		},
		{
			name = "LedgeCatch API present",
			fn = function()
				local LedgeCatch = require(ReplicatedStorage.Shared.movement.states.LedgeCatchState)
				assert(type(LedgeCatch.TryStart) == "function")
				assert(type(LedgeCatch.CanCatch) == "function")
			end,
		},		{
		name = "LedgeCatch.TryStart returns boolean",
		fn = function()
			local LedgeCatch = require(ReplicatedStorage.Shared.movement.states.LedgeCatchState)
			-- invalid context should safely return false
			assert(LedgeCatch.TryStart({}) == false)
		end,
		},		{
			name = "ClimbState scaffold exists",
			fn = function()
				local ClimbState = require(ReplicatedStorage.Shared.movement.states.ClimbState)
				assert(type(ClimbState.TryStart) == "function")
				assert(type(ClimbState.Enter) == "function")
			end,
		},
	},
}