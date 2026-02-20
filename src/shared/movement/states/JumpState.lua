--!strict
--[[
	Class: JumpState
	Description: Airborne state. Player is not on ground and not wall-running, vaulting, or ledge-catching.

	Responsibilities:
	  • Enter: nothing — coyote time and jump buffer are computed in MovementController.
	  • Update: nothing — gravity is Roblox-native; airborne speed is inertia from last ground frame.
	  • Exit: reset WallRun step count (delegated to WallRunState.OnLand from MovementController landing block).

	Open/Closed: Add air-dashes (Gale Aspect), double-jump, air-stall, or aerial VFX here.
	Blocked by #78 (Aspect system) for Gale mid-air redirect.

	Dependencies: StateContext (type only)
]]

local JumpState = {}

export type StateContext = any

function JumpState.Enter(_ctx: StateContext)
	-- Future: play jump-launch VFX, disable footstep SFX.
end

function JumpState.Update(_dt: number, _ctx: StateContext)
	-- Coyote-time and jump-buffer countdown run in MovementController.
	-- Airborne VFX, Aspect air abilities, etc. go here when unlocked.
end

function JumpState.Exit(_ctx: StateContext)
	-- Future: play landing prep VFX (glow, charge up on approach).
end

return JumpState
