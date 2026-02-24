--!strict
-- WeaponService discipline/cross-training tests

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponService = require(ReplicatedStorage.Server.services.WeaponService)
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

return {
	name = "WeaponService Unit Tests",
	tests = {
		{
			name = "equipping works and allows cross-training",
			fn = function()
				-- create a fake player with a simple humanoid stub to satisfy validation
				local fakePlayer = {
					UserId = 42,
					Name = "Tester",
					Character = {
						FindFirstChildOfClass = function(_)
							return {Health = 100}
						end,
					},
				}

				-- stub registry so any weapon is valid
				local origHas = WeaponRegistry.Has
				local origGet = WeaponRegistry.Get
				WeaponRegistry.Has = function() return true end
				WeaponRegistry.Get = function(id)
					return {Id = id, WeightClass = "Heavy"}
				end

				-- stub player to Wayward discipline (Heavy not in their allowed list)
				local origState = StateService.GetPlayerData
				StateService.GetPlayerData = function()
					return {DisciplineId = "Wayward"}
				end

				-- attempt to equip; cross-training should warn but allow
				WeaponService.EquipWeapon(fakePlayer, "heavy_sword")
				assert(WeaponService.GetEquipped(fakePlayer) == "heavy_sword")

				-- restore stubs
				WeaponRegistry.Has = origHas
				WeaponRegistry.Get = origGet
				StateService.GetPlayerData = origState
			end,
		},
	},
}
