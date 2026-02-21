--!strict
--[[
	CombatState: Block
	Represents being in a blocking posture.  The state includes logic for
	draining posture over time and reacting to incoming hits (should be
	invoked by CombatController when the player enters a blocking action).

	For now this is a stub; it's primarily here to demonstrate the modular
	state structure that mirrors MovementController.
]]

local BlockState = {}
export type StateContext = any

function BlockState.Enter(ctx: StateContext)
	ctx.Blackboard.IsBlocking = true
end

function BlockState.Update(_dt: number, _ctx: StateContext) end
function BlockState.Exit(ctx: StateContext)
	ctx.Blackboard.IsBlocking = false
end

function BlockState.TryStart(ctx: StateContext): boolean
	-- return true if a block action should start; controller can call to test
	return false
end

return BlockState
