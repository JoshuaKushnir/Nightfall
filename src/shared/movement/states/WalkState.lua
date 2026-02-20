--!strict
--[[
	Class: WalkState
	Description: Grounded walking state. Player is moving at walk speed.

	Responsibilities:
	  • Enter / Exit: hooks for footstep sounds or VFX triggers (future).
	  • Update: nothing for now — WalkSpeed is applied by MovementController's acceleration block.

	Open/Closed: Add footstep sfx, footprint decals, stamina cost-on-walk here.

	Dependencies: StateContext (type only)
]]

local WalkState = {}

export type StateContext = any

function WalkState.Enter(_ctx: StateContext)
	-- Future: start footstep SFX, show dust particles, etc.
end

function WalkState.Update(_dt: number, _ctx: StateContext)
	-- Speed is managed by MovementController acceleration logic.
	-- Walk-specific overlays (footstep timing, terrain adaptation) go here.
end

function WalkState.Exit(_ctx: StateContext)
	-- Future: stop footstep SFX.
end

return WalkState
