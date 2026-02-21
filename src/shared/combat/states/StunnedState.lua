--!strict
--[[
	CombatState: Stunned
	Player cannot act; used for stun entries from parry, hit-stop, etc.

	This state is primarily driven by external triggers (CombatService or
	ActionController) and will automatically timeout after a configured
	duration.
]]

local StunnedState = {}
export type StateContext = any

function StunnedState.Enter(ctx: StateContext)
	ctx.Blackboard.IsStunned = true
end

function StunnedState.Update(_dt: number, _ctx: StateContext) end
function StunnedState.Exit(ctx: StateContext)
	ctx.Blackboard.IsStunned = false
end

function StunnedState.TryStart(ctx: StateContext): boolean
	-- controller may call this when a stun trigger occurs
	return false
end

return StunnedState
