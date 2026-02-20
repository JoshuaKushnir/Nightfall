--!strict
--[[
	Class: SprintState
	Description: Grounded sprint state. Player is moving at sprint speed (double-tap W primed).

	Responsibilities:
	  • Enter: Breath drain begins (handled by UpdateBreath in MovementController when isSprinting=true).
	  • Update: nothing — sprint speed and FOV are applied by MovementController.
	  • Exit: nothing — Breath drain stops naturally when isSprinting becomes false.

	Open/Closed: Add sprint-specific VFX (speed lines, dirt trails), Momentum chain link on
	sustained sprint, or Aspect-specific sprint modifiers here (Gale redirect, Ember ramp, etc.).
	Blocked by #78 (Aspect system) for Aspect-specific variants.

	Dependencies: StateContext (type only)
]]

local SprintState = {}

export type StateContext = any

function SprintState.Enter(_ctx: StateContext)
	-- Future: spawn speed-streak VFX, tighten FOV (FOV effect already in MovementController today).
end

function SprintState.Update(_dt: number, _ctx: StateContext)
	-- Sprint WalkSpeed ramping, Breath drain, and FOV are all in MovementController today.
	-- Sprint-specific overlays (screen FX, terrain sparks, Aspect trails) go here.
end

function SprintState.Exit(_ctx: StateContext)
	-- Future: clear speed-streak VFX.
end

return SprintState
