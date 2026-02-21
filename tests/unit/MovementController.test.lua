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