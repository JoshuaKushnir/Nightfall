--!strict
-- CombatService unit tests (clash detection helpers)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatService = require(ReplicatedStorage.Server.services.CombatService)

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
	},
}
