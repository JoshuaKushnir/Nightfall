--!strict
--[[
	CombatState: Attack
	Handles attack-specific logic such as hitbox spawning, combo tracking,
	and notifying CombatService.  Currently a stub; core logic lives elsewhere.

	Future work: move portion of ActionController's combo handling into this
	state so that new attack behaviors can be plugged in via open/closed modules.
]]

local AttackState = {}
export type StateContext = any

function AttackState.Enter(ctx: StateContext)
	-- could set ctx.Blackboard.IsAttacking = true
	ctx.Blackboard.IsAttacking = true
end

function AttackState.Update(_dt: number, _ctx: StateContext) end
function AttackState.Exit(ctx: StateContext)
	ctx.Blackboard.IsAttacking = false
end

function AttackState.TryStart(ctx: StateContext): boolean
	-- guarded by controller or ActionController; default refusals
	return false
end

return AttackState
