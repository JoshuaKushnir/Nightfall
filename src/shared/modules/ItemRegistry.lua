--!strict
--[[
	ItemRegistry.lua
	
	Auto-discovers all item ModuleScripts under ReplicatedStorage.Shared.items
	on first require, validates each against the ItemConfig schema, and exposes
	a read-only index keyed by item Id.
	
	Designed to be required safely by both server and client — it is purely
	read-only and performs no replication or state mutation.
	
	Usage:
		local ItemRegistry = require(ReplicatedStorage.Shared.modules.ItemRegistry)
	
		local trainingTool = ItemRegistry.Get("training_tool_strength_common")
		local drops    = ItemRegistry.GetByPool("WorldDrop")
		local all      = ItemRegistry.GetAll()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- We'll create a simple validator for item configs later if needed
-- For now, we assume the configs are valid

-- ─── Internal state ───────────────────────────────────────────────────────────

-- keyed by ItemConfig.Id
local _registry: {[string]: any} = {}
-- keyed by ItemConfig.Category — for grouping items by category
local _byCategory: {[string]: {[string]: any}} = {}
-- true once _Discover() has run
local _loaded = false

-- ─── Discovery ────────────────────────────────────────────────────────────────

--[[
	Register one already-validated config table into both indexes.
]]
local function _RegisterConfig(config: any, moduleName: string, stats: {discovered: number, rejected: number})
	if _registry[config.Id] then
		warn(("[ItemRegistry] Duplicate item Id '%s' in '%s' — skipping."):format(config.Id, moduleName))
		stats.rejected += 1
		return
	end

	_registry[config.Id] = config

	-- Index by logical Category if present
	local cat: string? = config.Category
	if cat and type(cat) == "string" then
		_byCategory[cat] = _byCategory[cat] or {}
		_byCategory[cat][config.Id] = config
	end

	stats.discovered += 1
	print(("[ItemRegistry] ✓ Registered: %s (%s / %s)"):format(
		config.Id, config.Rarity, config.Category))
end

--[[
	Recursively walk `folder`, requiring each ModuleScript and indexing it.
	Sub-Folders are treated as item-class groupings, e.g.:
		items/TrainingTools/StrengthCommon.lua  →  Category = "TrainingTools"
]]
local function _DiscoverFolder(folder: Instance, stats: {discovered: number, rejected: number})
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") then
			_DiscoverFolder(child, stats) -- recurse
		elseif child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if not ok then
				warn(("[ItemRegistry] Failed to require '%s': %s"):format(child.Name, tostring(result)))
				stats.rejected += 1
				continue
			end

			-- TODO: Add item validation here when we have an ItemValidator
			-- For now, we assume the config is valid
			local valid = true
			local err = nil

			-- Basic validation: check required fields
			if not config.Id or type(config.Id) ~= "string" then
				err = "Missing or invalid 'Id' field"
				valid = false
			elseif not config.Category or type(config.Category) ~= "string" then
				err = "Missing or invalid 'Category' field"
				valid = false
			elseif config.Category == "Tools" then
				-- Training tools need additional validation
				if not config.StatToIncrease or type(config.StatToIncrease) ~= "string" then
					err = "Training tool missing 'StatToIncrease'"
					valid = false
				elseif type(config.Amount) ~= "number" or config.Amount <= 0 then
					err = "Training tool missing or invalid 'Amount'"
					valid = false
				end
			end
			if not valid then
				warn(("[ItemRegistry] Invalid item module '%s':\n  - %s"):format(
					child.Name, tostring(err)))
				stats.rejected += 1
				continue
			end

			_RegisterConfig(result :: any, child.Name, stats)
		end
	end
end

--[[
	Walk ReplicatedStorage.Shared.items (and all sub-Folders), require each
	ModuleScript, validate it, and index it by Id and by Category.
	
	Invalid modules are warned and skipped — they do not prevent other
	items from loading.
]]
local function _Discover()
	if _loaded then return end
	_loaded = true

	local itemsFolder = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("items")

	if not itemsFolder then
		warn("[ItemRegistry] ReplicatedStorage.Shared.items folder not found — no items will be registered.")
		return
	end

	local stats = {discovered = 0, rejected = 0}

	_DiscoverFolder(itemsFolder, stats)

	print(("[ItemRegistry] Discovery complete — %d registered, %d skipped"):format(
		stats.discovered, stats.rejected))
end

-- ─── Public API ───────────────────────────────────────────────────────────────

local ItemRegistry = {}

--[[
	Return the ItemConfig for the given Id, or nil if not found.
	
	@param id string — the item's Id field (e.g. "training_tool_strength_common")
	@return ItemConfig? 
]]
function ItemRegistry.Get(id: string): any?
	_Discover()
	return _registry[id]
end

--[[
	Return an array of all registered ItemConfigs.
	
	@return {ItemConfig}
]]
function ItemRegistry.GetAll(): {any}
	_Discover()
	local result: {any} = {}
	for _, config in _registry do
		table.insert(result, config)
	end
	return result
end

--[[
	Return an array of ItemConfigs whose LootPools array contains poolName.
	
	@param poolName string — e.g. "WorldDrop", "BanditChest"
	@return {ItemConfig}
]]
function ItemRegistry.GetByPool(poolName: string): {any}
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
	Return an array of ItemConfigs matching the given Category.
	
	@param category "Tools"|"Consumables"|etc.
	@return {ItemConfig}
]]
function ItemRegistry.GetByCategory(category: string): {any}
	_Discover()
	return _byCategory[category] or {}
end

--[[
	Returns true if an item with the given Id has been registered.
	
	@param id string
	@return boolean
]]
function ItemRegistry.Has(id: string): boolean
	_Discover()
	return _registry[id] ~= nil
end

--[[
	Force re-discovery (primarily useful in live-reload / test scenarios).
	Not needed under normal operation.
]]
function ItemRegistry._Reload()
	_loaded = false
	_registry = {}
	_byCategory = {}
	_Discover()
	print("[ItemRegistry] Reloaded.")
end

return ItemRegistry