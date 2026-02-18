--!strict
--[[
	LootLibrary.lua

	Issue #70: Loot Pool System
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Provides rarity-weighted random weapon selection from named loot pools.
	All weapon configs come from WeaponRegistry — pools and rarities are
	defined on each WeaponConfig via the `Pools` and `Rarity` fields.

	Rarity weights (configurable via RARITY_WEIGHTS):
		Common     = 60%
		Uncommon   = 25%
		Rare       = 12%
		Legendary  =  3%

	Usage:
		local LootLibrary = require(ReplicatedStorage.Shared.modules.LootLibrary)

		-- Roll any weapon from the "WorldDrop" pool
		local config = LootLibrary.Roll("WorldDrop")
		if config then
			print(config.Id, config.Rarity)
		end

		-- Roll with a forced-rarity override
		local rare = LootLibrary.Roll("WorldDrop", { ForceRarity = "Rare" })

		-- Inspect pool contents directly
		local pool = LootLibrary.GetPool("WorldDrop")

		-- Get the current rarity weight table
		local weights = LootLibrary.GetRarityWeights()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

local LootLibrary = {}

-- ─── Types ────────────────────────────────────────────────────────────────────

export type RollOptions = {
	-- When set, override the rarity lottery and only return weapons of this rarity.
	ForceRarity: string?,
}

-- ─── Constants ────────────────────────────────────────────────────────────────

-- Total should sum to 100 for readability, but the code normalises at runtime.
local RARITY_WEIGHTS: {[string]: number} = {
	Common    = 60,
	Uncommon  = 25,
	Rare      = 12,
	Legendary =  3,
}

-- Order used when printing or iterating rarities from lowest to highest tier.
local RARITY_ORDER: {string} = { "Common", "Uncommon", "Rare", "Legendary" }

-- ─── Private helpers ─────────────────────────────────────────────────────────

--[[
	Build a cumulative-weight table from RARITY_WEIGHTS filtered to only the
	rarities that actually appear in `candidates`.

	Returns:
		buckets  - { { rarity: string, ceiling: number } } sorted ascending by ceiling
		total    - the sum of all included weights

	Example (full set):
		{ { "Common",60 }, { "Uncommon",85 }, { "Rare",97 }, { "Legendary",100 } }, 100
]]
local function _BuildBuckets(candidates: {any}): ({[number]: {rarity: string, ceiling: number}}, number)
	-- Collect rarities present in the candidate list
	local present: {[string]: boolean} = {}
	for _, cfg in candidates do
		present[cfg.Rarity] = true
	end

	local buckets: {[number]: {rarity: string, ceiling: number}} = {}
	local running = 0

	for _, rarity in RARITY_ORDER do
		if present[rarity] and RARITY_WEIGHTS[rarity] then
			running += RARITY_WEIGHTS[rarity]
			table.insert(buckets, { rarity = rarity, ceiling = running })
		end
	end

	return buckets, running
end

--[[
	Given cumulative buckets and a total, pick a rarity string by rolling
	a value in [0, total).
]]
local function _RollRarity(buckets: {[number]: {rarity: string, ceiling: number}}, total: number): string
	local roll = math.random() * total
	for _, bucket in buckets do
		if roll < bucket.ceiling then
			return bucket.rarity
		end
	end
	-- Safety fallback: return the last bucket's rarity
	return buckets[#buckets].rarity
end

--[[
	Pick a uniformly random element from `list`.
	Returns nil when the list is empty.
]]
local function _PickRandom(list: {any}): any?
	if #list == 0 then return nil end
	return list[math.random(1, #list)]
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Return all weapon configs registered to the given pool name.
	Delegates to WeaponRegistry.GetByPool.

	@param poolName  Pool Id string (e.g. "WorldDrop", "BossChest").
	@return {WeaponConfig}
]]
function LootLibrary.GetPool(poolName: string): {any}
	return WeaponRegistry.GetByPool(poolName)
end

--[[
	Return the rarity weight table (a shallow copy).
	Keys are rarity strings, values are relative weights.

	@return {[string]: number}
]]
function LootLibrary.GetRarityWeights(): {[string]: number}
	local copy: {[string]: number} = {}
	for k, v in RARITY_WEIGHTS do
		copy[k] = v
	end
	return copy
end

--[[
	Roll a random weapon from the named pool using rarity-weighted selection.

	Steps:
	  1. Fetch all weapons in `poolName` from WeaponRegistry.
	  2. If `options.ForceRarity` is set, filter to only that rarity.
	     Skip the lottery and pick uniformly from that subset.
	  3. Otherwise run the rarity lottery using RARITY_WEIGHTS (only for
	     rarities actually present in the pool), then pick uniformly
	     from the winners.
	  4. Return nil (with a warning) when no weapon can be selected.

	@param poolName  Pool Id string.
	@param options   Optional RollOptions table.
	@return WeaponConfig?
]]
function LootLibrary.Roll(poolName: string, options: RollOptions?): any?
	local candidates = WeaponRegistry.GetByPool(poolName)

	if #candidates == 0 then
		warn(("[LootLibrary] Pool '%s' is empty or does not exist."):format(poolName))
		return nil
	end

	-- ── Forced rarity path ──────────────────────────────────────────────────
	if options and options.ForceRarity then
		local forced = options.ForceRarity
		local filtered: {any} = {}
		for _, cfg in candidates do
			if cfg.Rarity == forced then
				table.insert(filtered, cfg)
			end
		end

		if #filtered == 0 then
			warn(("[LootLibrary] Pool '%s' has no weapons with rarity '%s'."):format(poolName, forced))
			return nil
		end

		local winner = _PickRandom(filtered)
		return winner
	end

	-- ── Weighted rarity lottery ─────────────────────────────────────────────
	local buckets, total = _BuildBuckets(candidates)

	if total <= 0 or #buckets == 0 then
		-- All candidates have unweighted rarities; fall back to uniform pick.
		warn(("[LootLibrary] Pool '%s': no RARITY_WEIGHTS match — using uniform random."):format(poolName))
		return _PickRandom(candidates)
	end

	local chosenRarity = _RollRarity(buckets, total)

	-- Collect all candidates of the chosen rarity
	local winners: {any} = {}
	for _, cfg in candidates do
		if cfg.Rarity == chosenRarity then
			table.insert(winners, cfg)
		end
	end

	if #winners == 0 then
		-- Shouldn't happen, but guard anyway
		warn(("[LootLibrary] Rarity lottery picked '%s' but no candidates matched — using uniform random."):format(chosenRarity))
		return _PickRandom(candidates)
	end

	return _PickRandom(winners)
end

return LootLibrary
