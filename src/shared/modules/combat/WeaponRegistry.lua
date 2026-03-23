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
		local WeaponRegistry = require(ReplicatedStorage.Shared.modules.combat.WeaponRegistry)

		local sword = WeaponRegistry.Get("iron_sword")
		local drops  = WeaponRegistry.GetByPool("WorldDrop")
		local all    = WeaponRegistry.GetAll()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponValidator = require(ReplicatedStorage.Shared.modules.combat.WeaponValidator)

-- Import types for annotation only (no runtime cost)
local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = typeof(WeaponTypesModule) -- dummy; real type is WeaponTypes.WeaponConfig

-- ─── Internal state ───────────────────────────────────────────────────────────

-- keyed by WeaponConfig.Id
local _registry: {[string]: any} = {}
-- keyed by WeaponConfig.Class — issue #171: weapon-class hierarchy
local _byClass: {[string]: {[string]: any}} = {}
-- true once _Discover() has run
local _loaded = false

-- ─── Discovery ────────────────────────────────────────────────────────────────

--[[
	Register one already-validated config table into both indexes.
]]
local function _RegisterConfig(config: any, moduleName: string, stats: {discovered: number, rejected: number})
	if _registry[config.Id] then
		warn(("[WeaponRegistry] Duplicate weapon Id '%s' in '%s' — skipping."):format(config.Id, moduleName))
		stats.rejected += 1
		return
	end

	_registry[config.Id] = config

	-- Index by logical Class if present (issue #171)
	local cls: string? = config.Class
	if cls and type(cls) == "string" then
		_byClass[cls] = _byClass[cls] or {}
		_byClass[cls][config.Id] = config
	end

	stats.discovered += 1
	print(("[WeaponRegistry] ✓ Registered: %s (%s / %s)"):format(
		config.Id, config.Rarity, config.ToolType))
end

--[[
	Recursively walk `folder`, requiring each ModuleScript and indexing it.
	Sub-Folders are treated as weapon-class groupings, e.g.:
		weapons/Sword/IronSabre.lua  →  Class = "Sword"
]]
local function _DiscoverFolder(folder: Instance, stats: {discovered: number, rejected: number})
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") then
			_DiscoverFolder(child, stats) -- recurse
		elseif child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if not ok then
				warn(("[WeaponRegistry] Failed to require '%s': %s"):format(child.Name, tostring(result)))
				stats.rejected += 1
				continue
			end

			local valid, err = WeaponValidator.Validate(result)
			if not valid then
				warn(("[WeaponRegistry] Invalid weapon module '%s':\n  - %s"):format(
					child.Name, tostring(err)))
				stats.rejected += 1
				continue
			end

			_RegisterConfig(result :: any, child.Name, stats)
		end
	end
end

--[[
	Walk ReplicatedStorage.Shared.weapons (and all sub-Folders), require each
	ModuleScript, validate it, and index it by Id and by Class.

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

	local stats = {discovered = 0, rejected = 0}

	_DiscoverFolder(weaponsFolder, stats)

	print(("[WeaponRegistry] Discovery complete — %d registered, %d skipped"):format(
		stats.discovered, stats.rejected))
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

-- Returns all registered weapon configs for the given class name (e.g. "Sword", "Dagger").
function WeaponRegistry.GetClass(class: string): {[string]: any}
	_Discover()
	return _byClass[class] or {}
end

--[[
	Force re-discovery (primarily useful in live-reload / test scenarios).
	Not needed under normal operation.
]]
function WeaponRegistry._Reload()
	_loaded = false
	_registry = {}
	_byClass = {}
	_Discover()
	print("[WeaponRegistry] Reloaded.")
end

return WeaponRegistry
