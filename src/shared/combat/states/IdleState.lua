--!strict
--[[
	CombatState: Idle
	Description: Default neutral state when not performing any combat action.

	This module is intentionally minimal; it exists so the controller can fall
	through to a known state and so future idle-specific behavior can be added
	without touching the controller directly.
]]

local IdleState = {}

export type StateContext = any -- defined by CombatController

function IdleState.Enter(_ctx: StateContext) end
function IdleState.Update(_dt: number, _ctx: StateContext) end
function IdleState.Exit(_ctx: StateContext) end

-- input-driven trigger (may be called by controller each frame)
function IdleState.TryStart(_ctx: StateContext): boolean
	return false
end

return IdleState
