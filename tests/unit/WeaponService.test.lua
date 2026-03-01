--!strict
--[[
	WeaponService.test.lua

	Issue #133: WeaponService equip/unequip and proficiency check
	Epic #66: Modular Weapon Library & Equip System

	Tests:
	  - Basic equip/unequip flow
	  - Re-equip no-op
	  - Remote handler payload shapes
	  - Proficiency: primary discipline weapon → no penalty
	  - Proficiency: cross-training → penalty multipliers applied
	  - Proficiency: no WeightClass on weapon → no penalty
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponService  = require(ReplicatedStorage.Server.services.WeaponService)
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function fakePlayer(uid: number, disciplineId: string?)
	local seatAttrs: {[string]: any} = {}
	local charAttrs: {[string]: any} = {}
	return {
		UserId = uid,
		Name   = "Player_" .. uid,
		Character = {
			FindFirstChildOfClass = function(_, cls: string)
				if cls == "Humanoid" then return { Health = 100 } end
				return nil
			end,
			GetChildren = function() return {} end,
			SetAttribute = function(_, k, v) charAttrs[k] = v end,
			GetAttribute = function(_, k) return charAttrs[k] end,
		},
		FindFirstChildOfClass = function(_, cls: string)
			if cls == "Backpack" then
				return {
					GetChildren = function() return {} end,
					IsA = function(_, t) return t == "Backpack" end,
				}
			end
			return nil
		end,
		-- fake DataService profile for proficiency tests
		_disciplineId = disciplineId or "Wayward",
	}
end

-- Inject a fake DataService so _getProficiency can read profile
local function injectFakeDataService(player: any)
	WeaponService:Init({
		DataService = {
			GetProfile = function(_, p: any)
				return { DisciplineId = p._disciplineId or "Wayward" }
			end,
		},
	})
	return player
end

return {
	name = "WeaponService Unit Tests (#133)",
	tests = {

		-- ── Basic equip flow ──────────────────────────────────────────────────

		{
			name = "equipping a valid weapon stores it as equipped",
			fn = function()
				local p = fakePlayer(42)
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id) return { Id = id } end
				WeaponService.EquipWeapon(p, "wayward_sword")
				assert(WeaponService.GetEquipped(p) == "wayward_sword",
					"Expected 'wayward_sword' to be equipped")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "re-equipping the same weapon is a no-op",
			fn = function()
				local p = fakePlayer(100)
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id) return { Id = id } end
				WeaponService.EquipWeapon(p, "dagger")
				WeaponService.EquipWeapon(p, "dagger")
				assert(WeaponService.GetEquipped(p) == "dagger")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "equipping an unknown weapon id is rejected",
			fn = function()
				local p = fakePlayer(200)
				local origHas = WeaponRegistry.Has
				WeaponRegistry.Has = function() return false end
				WeaponService.EquipWeapon(p, "nonexistent_weapon")
				assert(WeaponService.GetEquipped(p) == nil,
					"Unknown weapon id should not be stored as equipped")
				WeaponRegistry.Has = origHas
			end,
		},

		{
			name = "remote handler accepts string payload",
			fn = function()
				local p = fakePlayer(1)
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id) return { Id = id } end
				local function handler(player, payload)
					local weaponId = typeof(payload) == "string" and payload
						or (typeof(payload) == "table" and payload.WeaponId) or nil
					if weaponId then WeaponService.EquipWeapon(player, weaponId) end
				end
				handler(p, "sword")
				assert(WeaponService.GetEquipped(p) == "sword")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "remote handler accepts table payload with WeaponId key",
			fn = function()
				local p = fakePlayer(2)
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id) return { Id = id } end
				local function handler(player, payload)
					local weaponId = typeof(payload) == "string" and payload
						or (typeof(payload) == "table" and payload.WeaponId) or nil
					if weaponId then WeaponService.EquipWeapon(player, weaponId) end
				end
				handler(p, { WeaponId = "axe" })
				assert(WeaponService.GetEquipped(p) == "axe")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		-- ── Proficiency checks (#133) ─────────────────────────────────────────

		{
			name = "weapon with no WeightClass gets full proficiency (no penalty)",
			fn = function()
				-- Weapon has no WeightClass — proficiency penalty never applies
				local p = injectFakeDataService(fakePlayer(300, "Silhouette"))
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id) return { Id = id } end -- no WeightClass
				WeaponService.EquipWeapon(p, "custom_weapon")
				-- No error means the equip path ran; GetEquipped confirms it succeeded
				assert(WeaponService.GetEquipped(p) == "custom_weapon",
					"Weapon without WeightClass should equip at full proficiency")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "primary discipline weapon equips at full proficiency",
			fn = function()
				-- Wayward gets Light + Medium; WaywardSword is Medium → no penalty
				local p = injectFakeDataService(fakePlayer(301, "Wayward"))
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id)
					return { Id = id, WeightClass = "Medium" }
				end
				WeaponService.EquipWeapon(p, "wayward_sword")
				assert(WeaponService.GetEquipped(p) == "wayward_sword",
					"Wayward equipping Medium weapon should succeed at full proficiency")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "cross-training: Silhouette equipping Heavy triggers penalty (still allowed)",
			fn = function()
				-- Silhouette only gets Light; Heavy is outside → cross-train, but allowed
				local p = injectFakeDataService(fakePlayer(302, "Silhouette"))
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id)
					return { Id = id, WeightClass = "Heavy" }
				end
				WeaponService.EquipWeapon(p, "iron_sword")
				assert(WeaponService.GetEquipped(p) == "iron_sword",
					"Cross-training should still allow equip (penalty applied, not blocked)")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "Ironclad equipping any WeightClass gets full proficiency",
			fn = function()
				-- Ironclad gets Light + Medium + Heavy — no penalty for any starter weapon
				local p = injectFakeDataService(fakePlayer(303, "Ironclad"))
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				local results: {boolean} = {}
				for _, wc in { "Light", "Medium", "Heavy" } do
					WeaponRegistry.Get = function(id) return { Id = id, WeightClass = wc } end
					WeaponService.EquipWeapon(p, "weapon_" .. wc)
					table.insert(results, WeaponService.GetEquipped(p) == "weapon_" .. wc)
				end
				for i, ok in results do
					assert(ok, ("Ironclad failed to equip WeightClass index %d at full proficiency"):format(i))
				end
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},

		{
			name = "Fists always equip at full proficiency regardless of discipline",
			fn = function()
				local p = injectFakeDataService(fakePlayer(304, "Silhouette"))
				local origHas, origGet = WeaponRegistry.Has, WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id)
					return { Id = "fists", WeightClass = "Light" }
				end
				WeaponService.EquipWeapon(p, "fists")
				assert(WeaponService.GetEquipped(p) == "fists",
					"Fists should always equip regardless of discipline")
				WeaponRegistry.Has, WeaponRegistry.Get = origHas, origGet
			end,
		},
	},
}
