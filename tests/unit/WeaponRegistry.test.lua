--!strict
--[[
	WeaponRegistry.test.lua

	Issue #132: WeaponRegistry — define 5 starter weapons
	Epic #66: Modular Weapon Library & Equip System

	Verifies that all five starter weapon definitions are valid and
	can be required without errors. Runs against the raw module tables
	(no Roblox services required) and uses WeaponValidator directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponValidator = require(ReplicatedStorage.Shared.modules.WeaponValidator)

-- ── Require all five starter weapon modules ──────────────────────────────────
local Fists         = require(ReplicatedStorage.Shared.weapons.Fists)
local IronSword     = require(ReplicatedStorage.Shared.weapons.IronSword)
local WaywardSword  = require(ReplicatedStorage.Shared.weapons.WaywardSword)
local SilhouetteDagger = require(ReplicatedStorage.Shared.weapons.SilhouetteDagger)
local ResonantStaff = require(ReplicatedStorage.Shared.weapons.ResonantStaff)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function expectValid(weapon: any, label: string)
	local ok, err = WeaponValidator.Validate(weapon)
	assert(ok, ("[WeaponRegistry.test] %s failed validation: %s"):format(label, tostring(err)))
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

return {
	name = "WeaponRegistry Starter Weapons",
	tests = {

		-- ── Individual validation ─────────────────────────────────────────────

		{
			name = "Fists passes WeaponValidator",
			fn = function()
				expectValid(Fists, "Fists")
			end,
		},

		{
			name = "IronSword passes WeaponValidator",
			fn = function()
				expectValid(IronSword, "IronSword")
			end,
		},

		{
			name = "WaywardSword passes WeaponValidator",
			fn = function()
				expectValid(WaywardSword, "WaywardSword")
			end,
		},

		{
			name = "SilhouetteDagger passes WeaponValidator",
			fn = function()
				expectValid(SilhouetteDagger, "SilhouetteDagger")
			end,
		},

		{
			name = "ResonantStaff passes WeaponValidator",
			fn = function()
				expectValid(ResonantStaff, "ResonantStaff")
			end,
		},

		-- ── Unique IDs ────────────────────────────────────────────────────────

		{
			name = "All five weapons have unique Ids",
			fn = function()
				local weapons = { Fists, IronSword, WaywardSword, SilhouetteDagger, ResonantStaff }
				local seen: {[string]: boolean} = {}
				for _, w in weapons do
					assert(w and type(w.Id) == "string" and w.Id ~= "", "Weapon must have a non-empty Id")
					assert(not seen[w.Id], ("Duplicate weapon Id: '%s'"):format(w.Id))
					seen[w.Id] = true
				end
			end,
		},

		-- ── Stat sanity ───────────────────────────────────────────────────────

		{
			name = "Each weapon has positive BaseDamage and AttackSpeed",
			fn = function()
				local weapons = { Fists, IronSword, WaywardSword, SilhouetteDagger, ResonantStaff }
				for _, w in weapons do
					assert(type(w.BaseDamage) == "number" and w.BaseDamage > 0,
						("'%s'.BaseDamage must be > 0"):format(w.Id))
					assert(type(w.AttackSpeed) == "number" and w.AttackSpeed > 0,
						("'%s'.AttackSpeed must be > 0"):format(w.Id))
				end
			end,
		},

		{
			name = "Fists has empty LootPools (not droppable)",
			fn = function()
				assert(type(Fists.LootPools) == "table" and #Fists.LootPools == 0,
					"Fists LootPools must be empty — it is not a droppable weapon")
			end,
		},

		{
			name = "WaywardSword is lighter than IronSword",
			fn = function()
				local waywardWeight = WaywardSword.Weight or 1.0
				local ironWeight    = IronSword.Weight    or 1.0
				assert(waywardWeight < ironWeight,
					("WaywardSword.Weight (%.2f) should be lighter than IronSword.Weight (%.2f)"):format(
						waywardWeight, ironWeight))
			end,
		},

		{
			name = "SilhouetteDagger has the highest AttackSpeed",
			fn = function()
				local weapons = { Fists, IronSword, WaywardSword, SilhouetteDagger, ResonantStaff }
				local daggerSpeed = SilhouetteDagger.AttackSpeed
				for _, w in weapons do
					if w.Id ~= SilhouetteDagger.Id then
						assert(daggerSpeed >= w.AttackSpeed,
							("SilhouetteDagger.AttackSpeed (%.2f) should be >= '%s'.AttackSpeed (%.2f)"):format(
								daggerSpeed, w.Id, w.AttackSpeed))
					end
				end
			end,
		},

		{
			name = "ResonantStaff has the longest Range",
			fn = function()
				local weapons = { Fists, IronSword, WaywardSword, SilhouetteDagger, ResonantStaff }
				local staffRange = ResonantStaff.Range
				for _, w in weapons do
					if w.Id ~= ResonantStaff.Id then
						assert(staffRange >= w.Range,
							("ResonantStaff.Range (%.2f) should be >= '%s'.Range (%.2f)"):format(
								staffRange, w.Id, w.Range))
					end
				end
			end,
		},

		-- ── Combo length ──────────────────────────────────────────────────────

		{
			name = "SilhouetteDagger has the longest combo (6 hits)",
			fn = function()
				assert(#SilhouetteDagger.Animations.Combo == 6,
					("SilhouetteDagger combo should have 6 hits, got %d"):format(
						#SilhouetteDagger.Animations.Combo))
			end,
		},

		{
			name = "ResonantStaff has the shortest combo (2 hits)",
			fn = function()
				assert(#ResonantStaff.Animations.Combo == 2,
					("ResonantStaff combo should have 2 hits, got %d"):format(
						#ResonantStaff.Animations.Combo))
			end,
		},
	},
}
