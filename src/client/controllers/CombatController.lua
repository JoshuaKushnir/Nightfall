--!strict
--[[
	CombatController.lua

	Issue #???: Advanced Combat State Machine
	Epic: Phase 2 - Combat & Fluidity (refactor)

	Client-side controller that mirrors the movement system's modular
	state infrastructure.  Each combat "state" (Idle, Attack, Block, Stunned,
	etc.) lives in its own module under Shared.combat.states.  The controller
	resolves which state should be active each frame, calls the state's
	Enter/Update/Exit hooks, and exposes a context table for shared helpers.

	Other systems (ActionController, PlayerHUDController, VFX handlers)
	read from CombatBlackboard to react to combat state changes.

	This scaffold is the foundation for future work: clash follow-ups,
	combos, stunned/parry windows, etc.  The goal is to decouple combat
	behaviour from the monolithic ActionController and allow open/closed
	extensibility similar to movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatBlackboard = require(ReplicatedStorage.Shared.modules.CombatBlackboard)

-- safeRequire helper (copied from MovementController)
local function safeRequire(moduleInstance, name)
	local ok, result = pcall(require, moduleInstance)
	if ok then
		return result
	end
	warn(("[CombatController] ⚠ State module '%s' failed to load — stubbed out. Error: %s"):format(name, tostring(result)))
	return {
		Enter = function() end,
		Update = function() end,
		Exit = function() end,
		TryStart = function(): boolean return false end,
	}
end

local IdleState       = safeRequire(ReplicatedStorage.Shared.combat.states.IdleState,       "IdleState")
local AttackState     = safeRequire(ReplicatedStorage.Shared.combat.states.AttackState,     "AttackState")
local BlockState      = safeRequire(ReplicatedStorage.Shared.combat.states.BlockState,      "BlockState")
local StunnedState    = safeRequire(ReplicatedStorage.Shared.combat.states.StunnedState,    "StunnedState")
-- additional states such as ParryState, BreakState may be added later

local CombatController = {}

-- State bookkeeping
local _currentStateName: string = "Idle"
local _stateModules: {[string]: any} = {
	Idle    = IdleState,
	Attack  = AttackState,
	Block   = BlockState,
	Stunned = StunnedState,
}

local function _resolveActiveState(blackboard: any): string
	-- priority order: Stunned > Attack > Block > Idle
	if blackboard.IsStunned then return "Stunned" end
	if blackboard.IsAttacking then return "Attack" end
	if blackboard.IsBlocking then return "Block" end
	return "Idle"
end

local function _buildCtx(): any
	return {
		Blackboard = CombatBlackboard,
		-- additional helpers can be added here, e.g. networking, animation, etc.
	}
end

function CombatController:Init(dependencies: {[string]: any}?)
	-- no dependencies right now, placeholder for symmetry with MovementController
end

function CombatController:Start()
	-- update loop
	local last = tick()
	RunService.Heartbeat:Connect(function()
		local now = tick()
		local dt = now - last
		last = now

		-- state resolution
		local newState = _resolveActiveState(CombatBlackboard)
		if newState ~= _currentStateName then
			-- exit old
			local prevModule = _stateModules[_currentStateName]
			if prevModule and prevModule.Exit then
				prevModule.Exit(_buildCtx())
			end
			-- enter new
			local newModule = _stateModules[newState]
			if newModule and newModule.Enter then
				newModule.Enter(_buildCtx())
			end
			CombatBlackboard.ActiveState = newState
			_currentStateName = newState
		end

		-- update current state module
		local mod = _stateModules[_currentStateName]
		if mod and mod.Update then
			mod.Update(dt, _buildCtx())
		end
	end)
end

-- External API --------------------------------------------------

function CombatController.GetCurrentState(): string
	return _currentStateName
end

function CombatController.NotifyActionStarted(config: any)
	-- simple mapping: when an attack begins, set flag on blackboard
	if config.Type == "Attack" then
		CombatBlackboard.IsAttacking = true
	elseif config.Type == "Block" then
		CombatBlackboard.IsBlocking = true
	elseif config.Type == "Parry" then
		-- could set IsParrying or trigger a dedicated state
	end
end

function CombatController.NotifyActionEnded(config: any)
	if config.Type == "Attack" then
		CombatBlackboard.IsAttacking = false
	elseif config.Type == "Block" then
		CombatBlackboard.IsBlocking = false
	end
end

function CombatController.TriggerStun(duration: number)
	CombatBlackboard.IsStunned = true
	-- schedule exit after duration
	task.delay(duration, function()
		CombatBlackboard.IsStunned = false
	end)
end

return CombatController
