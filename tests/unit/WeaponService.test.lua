--!strict
-- WeaponService discipline restriction tests

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponService = require(ReplicatedStorage.Server.services.WeaponService)
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

return {
	name = "WeaponService Unit Tests",
	tests = {
		{
			name = "cannot equip weapon outside discipline weight class",
			fn = function()
				local fakePlayer = {UserId = 42, Name = "Tester", Character = {}}
				-- stub WeaponRegistry
				local origHas = WeaponRegistry.Has
				local origGet = WeaponRegistry.Get
				WeaponRegistry.Has = function(id) return id == "heavy_sword" end
				WeaponRegistry.Get = function(id)
					if id == "heavy_sword" then
						return {Id = id, WeightClass = "Heavy", Name = "Heavy Sword"}
					end
				end

				-- stub StateService to return Wayward discipline
				local origState = StateService.GetPlayerData
				StateService.GetPlayerData = function(_)
					return {DisciplineId = "Wayward"}
				end

				-- attempt to equip
				WeaponService.EquipWeapon(fakePlayer, "heavy_sword")
				-- since equip simply returns (no error), we inspect EquippedWeapons table via debug
				local equipExists = debug.getupvalue(WeaponService.EquipWeapon, 1)
				-- easier: rely on print side-effects not feasible; instead just assert that
				-- fakePlayer.UserId is not present in EquippedWeapons
				-- hack: use pcall to read global table defined earlier
				local equipped = nil
				for uid, id in pairs(_G) do
					-- ignore
				end
				-- easier: call WeaponService.GetEquipped which returns surprise nil when not equipped
				assert(WeaponService.GetEquipped(fakePlayer) == nil)

				-- restore stubs
				WeaponRegistry.Has = origHas
				WeaponRegistry.Get = origGet
				StateService.GetPlayerData = origState
			end,
		},
	},
}
