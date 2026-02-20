--!strict
--[[
	Class: IdleState
	Description: Default grounded rest state. Player is on-ground with no movement input.

	Responsibilities:
	  • Enter: nothing special — animation handled by MovementController's animation block.
	  • Update: nothing — all shared subsystems (Breath regen, Momentum decay) run in MovementController.
	  • Exit: nothing.

	Open/Closed: Drop new idle-specific behaviours here (idle fidgets, ambient footsteps, etc.)
	without touching MovementController.

	Dependencies: StateContext (type only)
]]

local IdleState = {}

export type StateContext = any -- resolved by consumer (avoids circular require)

function IdleState.Enter(_ctx: StateContext)
	-- Future: trigger idle blend animation, ambient particle reset, etc.
end

function IdleState.Update(_dt: number, _ctx: StateContext)
	-- Shared systems (Breath regen, Momentum decay) already run in MovementController.
	-- Idle-specific logic (pose blending, look-at-camera drift, etc.) goes here.
end

function IdleState.Exit(_ctx: StateContext)
	-- Future: cancel any idle-specific effects.
end

return IdleState
