--!strict
-- CombatService unit tests (clash detection helpers)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatService = require(ReplicatedStorage.Server.services.CombatService)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local WeaponService = require(ReplicatedStorage.Server.services.WeaponService)
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

return {
	name = "CombatService Unit Tests",
	tests = {
		{
			name = "clash helper registers and detects correctly",
			fn = function()
				local pA = {Name = "A"}
				local pB = {Name = "B"}

				-- initially no clash (no prior hits)
				assert(CombatService._DidClash(pA, pB, 0))

				-- register a hit from A -> B at time 1
				CombatService._RegisterHit(pA, pB, 1)

				-- time far outside window should not clash
				assert(not CombatService._DidClash(pB, pA, 10))

				-- time within very small delta should trigger clash
				assert(CombatService._DidClash(pB, pA, 1.02))

				-- verify handler can be invoked
				local seen = false
				CombatService._HandleClash = function(att, tgt)
					seen = true
				end
				CombatService._HandleClash(pA, pB)
				assert(seen)
			end,
		},
		{
			name = "Break damage formula respects discipline",
			fn = function()
				local orig = StateService.GetPlayerData
				StateService.GetPlayerData = function(_)
					return {DisciplineId = "Ironclad"}
				end

				local overflow = 10
				local dmg = CombatService.CalculateBreakDamage({UserId = 1}, overflow)
				local cfg = DisciplineConfig.Get("Ironclad")
				local expected = math.floor(cfg.breakBase + overflow * cfg.breakOverflowMult)
				assert(dmg == expected, "break damage did not match discipline formula")

				StateService.GetPlayerData = orig
			end,
		},
		{
			name = "Cross-train penalty reduces break damage",
			fn = function()
				-- stub discipline and equipped weapon
				local origState = StateService.GetPlayerData
				StateService.GetPlayerData = function(_)
					return {DisciplineId = "Wayward"}
				end

				local origEq = WeaponService.GetEquipped
				local origRegGet = WeaponRegistry.Get
				WeaponService.GetEquipped = function(_) return "heavy_sword" end
				WeaponRegistry.Get = function(id)
					return {Id = id, WeightClass = "Heavy"}
				end

				-- calculate damage with zero overflow
				local dmg = CombatService.CalculateBreakDamage({UserId = 2}, 0)
				local base = DisciplineConfig.Get("Wayward").breakBase
				local expected = math.floor(base * DisciplineConfig.crossTrainPenalty.hpDamageMult)
				assert(dmg == expected, "cross-train penalty not applied")

				-- restore stubs
				StateService.GetPlayerData = origState
				WeaponService.GetEquipped = origEq
				WeaponRegistry.Get = origRegGet
			end,
		},
	},
}
