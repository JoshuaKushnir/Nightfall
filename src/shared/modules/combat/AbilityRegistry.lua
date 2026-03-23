--!strict
--[[
	AbilityRegistry.lua
	Issue #72: Weapon abilities — active + passive framework
	Issue #149: Refactor aspect system to full attunement moveset

	Auto-discovers all ability ModuleScripts under
	ReplicatedStorage.Shared.abilities and indexes them by Id.

	Supports two module formats:
	  1. Single ability: module returns { Id, Type, ... }
	  2. Aspect moveset: module returns { AspectId, Moves = [{...}, ...] }
	     → each move is registered individually by its Id.

	Usage:
		local AbilityRegistry = require(ReplicatedStorage.Shared.modules.combat.AbilityRegistry)
		local ability = AbilityRegistry.Get("AshenStep")
		local moveset = AbilityRegistry.GetMoveset("Ash")
		local all     = AbilityRegistry.GetAll()
		local expr    = AbilityRegistry.GetByType("Expression")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityRegistry = {}

-- ─── Internal state ───────────────────────────────────────────────────────────

-- Flat map: abilityId → ability config
local _registry: {[string]: any} = {}

-- Moveset map: aspectId → moveset module (for GetMoveset)
local _movesets: {[string]: any} = {}

local _loaded = false

-- ─── Discovery ────────────────────────────────────────────────────────────────

local function _Discover()
	if _loaded then return end
	_loaded = true

	local abilitiesFolder = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("abilities")

	if not abilitiesFolder then
		warn("[AbilityRegistry] ReplicatedStorage.Shared.abilities not found — no abilities registered.")
		return
	end

	local registered = 0
	local skipped    = 0

	for _, child in abilitiesFolder:GetChildren() do
		if not child:IsA("ModuleScript") then continue end

		local ok, result = pcall(require, child)
		if not ok then
			warn(("[AbilityRegistry] Failed to require '%s': %s"):format(child.Name, tostring(result)))
			skipped += 1
			continue
		end

		if type(result) ~= "table" then
			warn(("[AbilityRegistry] '%s' must return a table"):format(child.Name))
			skipped += 1
			continue
		end

		-- ── Format 2: Aspect Moveset (has AspectId + Moves array) ───────────
		if result.AspectId ~= nil and type(result.Moves) == "table" then
			_movesets[result.AspectId] = result
			local moveCount = 0
			for _, move in ipairs(result.Moves) do
				if type(move) ~= "table" or not move.Id or not move.Type then
					warn(("[AbilityRegistry] Moveset '%s' has invalid move entry — skipping"):format(child.Name))
					skipped += 1
					continue
				end
				_registry[move.Id] = move
				registered += 1
				moveCount += 1
			end
			print(("[AbilityRegistry] ✓ Moveset registered: %s (%d moves)"):format(
				result.AspectId, moveCount))
			continue
		end

		-- ── Format 1: Single ability (has Id + Type) ────────────────────────
		if not result.Id or not result.Type then
			warn(("[AbilityRegistry] '%s' must return a table with Id and Type fields (or AspectId and Moves for a moveset)"):format(child.Name))
			skipped += 1
			continue
		end

		_registry[result.Id] = result
		registered += 1
		print(("[AbilityRegistry] ✓ Registered: %s (%s)"):format(result.Id, result.Type))
	end

	print(("[AbilityRegistry] Discovery complete — %d registered, %d skipped"):format(registered, skipped))
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Return the ability config for the given Id, or nil.
]]
function AbilityRegistry.Get(id: string): any?
	_Discover()
	return _registry[id]
end

--[[
	Return the full AspectMoveset for the given AspectId, or nil.
	This returns the raw moveset module (with .Moves array).
]]
function AbilityRegistry.GetMoveset(aspectId: string): any?
	_Discover()
	return _movesets[aspectId]
end

--[[
	Return all registered ability configs as an array.
]]
function AbilityRegistry.GetAll(): {any}
	_Discover()
	local result: {any} = {}
	for _, v in _registry do
		table.insert(result, v)
	end
	return result
end

--[[
	Return all abilities of a given Type ("Active", "Passive", or "Expression").
]]
function AbilityRegistry.GetByType(abilityType: string): {any}
	_Discover()
	local result: {any} = {}
	for _, v in _registry do
		if v.Type == abilityType then
			table.insert(result, v)
		end
	end
	return result
end

--[[
	Return all Expression abilities belonging to a given AspectId.
]]
function AbilityRegistry.GetMovesForAspect(aspectId: string): {any}
	_Discover()
	local result: {any} = {}
	for _, v in _registry do
		if v.AspectId == aspectId and v.Type == "Expression" then
			table.insert(result, v)
		end
	end
	-- Sort by Slot so callers get them in order
	table.sort(result, function(a, b)
		return (a.Slot or 0) < (b.Slot or 0)
	end)
	return result
end

--[[
	Returns true if an ability with this Id is registered.
]]
function AbilityRegistry.Has(id: string): boolean
	_Discover()
	return _registry[id] ~= nil
end

return AbilityRegistry
