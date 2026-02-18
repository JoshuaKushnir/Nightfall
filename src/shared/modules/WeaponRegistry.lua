--!strict
--[[
	WeaponRegistry.lua

	Issue #67: WeaponRegistry — auto-discovery and manifest index
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Auto-discovers all weapon ModuleScripts under ReplicatedStorage.Shared.weapons
	on first require, validates each against the WeaponConfig schema, and exposes
	a read-only index keyed by weapon Id.

	Designed to be required safely by both server and client — it is purely
	read-only and performs no replication or state mutation.

	Usage:
		local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

		local sword = WeaponRegistry.Get("iron_sword")
		local drops  = WeaponRegistry.GetByPool("WorldDrop")
		local all    = WeaponRegistry.GetAll()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponValidator = require(ReplicatedStorage.Shared.modules.WeaponValidator)

-- Import types for annotation only (no runtime cost)
local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = typeof(WeaponTypesModule) -- dummy; real type is WeaponTypes.WeaponConfig

-- ─── Internal state ───────────────────────────────────────────────────────────

-- keyed by WeaponConfig.Id
local _registry: {[string]: any} = {}
-- true once _Discover() has run
local _loaded = false

-- ─── Discovery ────────────────────────────────────────────────────────────────

--[[
	Walk ReplicatedStorage.Shared.weapons, require each ModuleScript,
	run it through WeaponValidator, and index valid configs by Id.

	Invalid modules are warned and skipped — they do not prevent other
	weapons from loading.
]]
local function _Discover()
	if _loaded then return end
	_loaded = true

	local weaponsFolder = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("weapons")

	if not weaponsFolder then
		warn("[WeaponRegistry] ReplicatedStorage.Shared.weapons folder not found — no weapons will be registered.")
		return
	end

	local discovered = 0
	local rejected   = 0

	for _, child in weaponsFolder:GetChildren() do
		if not child:IsA("ModuleScript") then continue end

		local ok, result = pcall(require, child)
		if not ok then
			warn(("[WeaponRegistry] Failed to require '%s': %s"):format(child.Name, tostring(result)))
			rejected += 1
			continue
		end

		local valid, err = WeaponValidator.Validate(result)
		if not valid then
			warn(("[WeaponRegistry] Invalid weapon module '%s':\n  - %s"):format(child.Name, tostring(err)))
			rejected += 1
			continue
		end

		local config = result :: any
		if _registry[config.Id] then
			warn(("[WeaponRegistry] Duplicate weapon Id '%s' in '%s' — skipping."):format(config.Id, child.Name))
			rejected += 1
			continue
		end

		_registry[config.Id] = config
		discovered += 1
		print(("[WeaponRegistry] ✓ Registered: %s (%s / %s)"):format(
			config.Id, config.Rarity, config.ToolType))
	end

	print(("[WeaponRegistry] Discovery complete — %d registered, %d skipped"):format(discovered, rejected))
end

-- ─── Public API ───────────────────────────────────────────────────────────────

local WeaponRegistry = {}

--[[
	Return the WeaponConfig for the given Id, or nil if not found.

	@param id string — the weapon's Id field (e.g. "iron_sword")
	@return WeaponConfig? 
]]
function WeaponRegistry.Get(id: string): any?
	_Discover()
	return _registry[id]
end

--[[
	Return an array of all registered WeaponConfigs.

	@return {WeaponConfig}
]]
function WeaponRegistry.GetAll(): {any}
	_Discover()
	local result: {any} = {}
	for _, config in _registry do
		table.insert(result, config)
	end
	return result
end

--[[
	Return an array of WeaponConfigs whose LootPools array contains poolName.

	@param poolName string — e.g. "WorldDrop", "BanditChest"
	@return {WeaponConfig}
]]
function WeaponRegistry.GetByPool(poolName: string): {any}
	_Discover()
	local result: {any} = {}
	for _, config in _registry do
		if config.LootPools then
			for _, pool in config.LootPools do
				if pool == poolName then
					table.insert(result, config)
					break
				end
			end
		end
	end
	return result
end

--[[
	Return an array of WeaponConfigs matching the given Rarity.

	@param rarity "Common"|"Uncommon"|"Rare"|"Legendary"
	@return {WeaponConfig}
]]
function WeaponRegistry.GetByRarity(rarity: string): {any}
	_Discover()
	local result: {any} = {}
	for _, config in _registry do
		if config.Rarity == rarity then
			table.insert(result, config)
		end
	end
	return result
end

--[[
	Returns true if a weapon with the given Id has been registered.

	@param id string
	@return boolean
]]
function WeaponRegistry.Has(id: string): boolean
	_Discover()
	return _registry[id] ~= nil
end

--[[
	Force re-discovery (primarily useful in live-reload / test scenarios).
	Not needed under normal operation.
]]
function WeaponRegistry._Reload()
	_loaded = false
	_registry = {}
	_Discover()
	print("[WeaponRegistry] Reloaded.")
end

return WeaponRegistry
