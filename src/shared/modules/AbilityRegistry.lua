--!strict
--[[
	AbilityRegistry.lua
	Issue #72: Weapon abilities — active + passive framework
	Epic #66: Modular Weapon Library & Equip System

	Auto-discovers all ability ModuleScripts under
	ReplicatedStorage.Shared.abilities and indexes them by Id.
	Follows the same lazy-discovery pattern as WeaponRegistry.

	Usage:
		local AbilityRegistry = require(ReplicatedStorage.Shared.modules.AbilityRegistry)
		local stagger = AbilityRegistry.Get("Stagger")
		local all     = AbilityRegistry.GetAll()
		local passives = AbilityRegistry.GetByType("Passive")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityRegistry = {}

-- ─── Internal state ───────────────────────────────────────────────────────────

local _registry: {[string]: any} = {}
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

		if type(result) ~= "table" or not result.Id or not result.Type then
			warn(("[AbilityRegistry] '%s' must return a table with Id and Type fields"):format(child.Name))
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
	Return all abilities of a given Type ("Active" or "Passive").
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
	Returns true if an ability with this Id is registered.
]]
function AbilityRegistry.Has(id: string): boolean
	_Discover()
	return _registry[id] ~= nil
end

return AbilityRegistry
