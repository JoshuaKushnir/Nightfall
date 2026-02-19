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
			name = "Double-tap toggles sprint on/off (ww)",
			fn = function()
				-- Verify API exists
				assert(type(MovementController._isSprinting) == "function")
				-- Integration test should simulate: double-tap W -> MovementController._isSprinting() == true
				-- then double-tap W again -> MovementController._isSprinting() == false
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
				assert(type(MovementController._OnJumpRequest) == "function")
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
	},
}