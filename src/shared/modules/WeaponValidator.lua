--!strict
--[[
	WeaponValidator.lua

	Issue #68: WeaponModule Schema — typed definition and validator
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Validates a raw table returned by a weapon ModuleScript against the
	WeaponConfig schema.  Used by WeaponRegistry before indexing any module.

	Usage:
		local WeaponValidator = require(ReplicatedStorage.Shared.modules.WeaponValidator)
		local ok, err = WeaponValidator.Validate(rawTable)
		if not ok then
			warn("[WeaponRegistry] Skipping invalid weapon: " .. tostring(err))
		end
]]

local WeaponValidator = {}

-- ─── Internal helpers ─────────────────────────────────────────────────────────

local VALID_RARITIES: {[string]: boolean} = {
	Common = true,
	Uncommon = true,
	Rare = true,
	Legendary = true,
}

local VALID_TOOL_TYPES: {[string]: boolean} = {
	Melee = true,
	Ranged = true,
	Magic = true,
}

-- Collect all errors into a list so callers get the full picture at once.
local function check(errors: {string}, condition: boolean, message: string)
	if not condition then
		table.insert(errors, message)
	end
end

local function isString(v: any): boolean
	return type(v) == "string"
end

local function isNumber(v: any): boolean
	return type(v) == "number"
end

local function isTable(v: any): boolean
	return type(v) == "table"
end

local function isVector3(v: any): boolean
	return typeof(v) == "Vector3"
end

local function isCFrame(v: any): boolean
	return typeof(v) == "CFrame"
end

local function validateAnimEntry(entry: any, path: string, errors: {string})
	if not isTable(entry) then
		table.insert(errors, path .. " must be a table {Folder, Asset, HitFrame?}")
		return
	end
	check(errors, isString(entry.Folder) and entry.Folder ~= "", path .. ".Folder must be a non-empty string")
	check(errors, isString(entry.Asset)  and entry.Asset  ~= "", path .. ".Asset must be a non-empty string")
	if entry.HitFrame ~= nil then
		check(errors, isNumber(entry.HitFrame) and entry.HitFrame >= 0 and entry.HitFrame <= 1,
			path .. ".HitFrame must be a number between 0 and 1")
	end
end

local function validateHitbox(hitbox: any, path: string, errors: {string})
	if not isTable(hitbox) then
		table.insert(errors, path .. " must be a table {Size: Vector3, Offset: CFrame}")
		return
	end
	check(errors, isVector3(hitbox.Size),  path .. ".Size must be a Vector3")
	check(errors, isCFrame(hitbox.Offset), path .. ".Offset must be a CFrame")
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
	Validate a raw weapon config table.

	@param config any — the raw value returned by a weapon ModuleScript
	@return boolean, string? — (true, nil) on success; (false, errorMessage) on failure
]]
function WeaponValidator.Validate(config: any): (boolean, string?)
	local errors: {string} = {}

	if not isTable(config) then
		return false, "Weapon module must return a table, got " .. typeof(config)
	end

	-- ── Identity ─────────────────────────────────────────────────────────────
	check(errors, isString(config.Id)          and config.Id          ~= "", "Id must be a non-empty string")
	check(errors, isString(config.Name)        and config.Name        ~= "", "Name must be a non-empty string")
	check(errors, isString(config.Description) and config.Description ~= "", "Description must be a non-empty string")

	-- ── Rarity & Loot ────────────────────────────────────────────────────────
	check(errors, isString(config.Rarity) and VALID_RARITIES[config.Rarity] == true,
		"Rarity must be one of: Common, Uncommon, Rare, Legendary")
	check(errors, isNumber(config.LootWeight) and config.LootWeight >= 0 and config.LootWeight <= 100,
		"LootWeight must be a number between 0 and 100")
	check(errors, isTable(config.LootPools),
		"LootPools must be an array (may be empty for non-loot weapons)")
	if isTable(config.LootPools) then
		for i, v in config.LootPools do
			check(errors, isString(v) and v ~= "", ("LootPools[%d] must be a non-empty string"):format(i))
		end
	end

	-- ── Tool ─────────────────────────────────────────────────────────────────
	check(errors, isString(config.ToolModelId), "ToolModelId must be a string")
	check(errors, isString(config.ToolType) and VALID_TOOL_TYPES[config.ToolType] == true,
		"ToolType must be one of: Melee, Ranged, Magic")
	if config.GripOffset ~= nil then
		check(errors, isCFrame(config.GripOffset), "GripOffset must be a CFrame")
	end

	-- ── Stats ────────────────────────────────────────────────────────────────
	check(errors, isNumber(config.BaseDamage)   and config.BaseDamage   > 0,  "BaseDamage must be a positive number")
	check(errors, isNumber(config.AttackSpeed)  and config.AttackSpeed  > 0,  "AttackSpeed must be a positive number")
	check(errors, isNumber(config.Range)        and config.Range        > 0,  "Range must be a positive number")
	if config.KnockbackPower ~= nil then
		check(errors, isNumber(config.KnockbackPower) and config.KnockbackPower >= 0,
			"KnockbackPower must be a non-negative number")
	end
	if config.Weight ~= nil then
		check(errors, isNumber(config.Weight) and config.Weight >= 0, "Weight must be a non-negative number")
	end

	-- ── Animations ───────────────────────────────────────────────────────────
	if not isTable(config.Animations) then
		table.insert(errors, "Animations must be a table")
	else
		local anims = config.Animations
		validateAnimEntry(anims.Equip, "Animations.Equip", errors)
		validateAnimEntry(anims.Idle,  "Animations.Idle",  errors)
		validateAnimEntry(anims.Walk,  "Animations.Walk",  errors)
		validateAnimEntry(anims.Run,   "Animations.Run",   errors)

		if not isTable(anims.Combo) or #anims.Combo == 0 then
			table.insert(errors, "Animations.Combo must be a non-empty array of animation entries")
		else
			for i, entry in anims.Combo do
				validateAnimEntry(entry, ("Animations.Combo[%d]"):format(i), errors)
			end
		end

		if anims.LungeAttack ~= nil then
			validateAnimEntry(anims.LungeAttack, "Animations.LungeAttack", errors)
		end
		if anims.HeavyAttack ~= nil then
			validateAnimEntry(anims.HeavyAttack, "Animations.HeavyAttack", errors)
		end
	end

	-- ── Hitboxes ─────────────────────────────────────────────────────────────
	if not isTable(config.Hitboxes) or next(config.Hitboxes) == nil then
		table.insert(errors, "Hitboxes must be a non-empty table keyed by attack type")
	else
		for key, hitbox in config.Hitboxes do
			validateHitbox(hitbox, ("Hitboxes[%q]"):format(key), errors)
		end
	end
	-- "Default" hitbox is required as the fallback
	if isTable(config.Hitboxes) then
		check(errors, config.Hitboxes["Default"] ~= nil,
			'Hitboxes must contain a "Default" entry as a fallback')
	end

	-- ── Abilities (optional) ─────────────────────────────────────────────────
	if config.Abilities ~= nil then
		check(errors, isTable(config.Abilities), "Abilities must be a table if provided")
		if isTable(config.Abilities) then
			if config.Abilities.Active ~= nil then
				check(errors, isString(config.Abilities.Active), "Abilities.Active must be a string")
			end
			if config.Abilities.Passive ~= nil then
				check(errors, isString(config.Abilities.Passive), "Abilities.Passive must be a string")
			end
		end
	end

	-- ── Effects (optional) ───────────────────────────────────────────────────
	if config.Effects ~= nil then
		check(errors, isTable(config.Effects), "Effects must be a table if provided")
	end

	-- ── Result ───────────────────────────────────────────────────────────────
	if #errors == 0 then
		return true, nil
	end
	return false, table.concat(errors, "\n  - ")
end

return WeaponValidator
