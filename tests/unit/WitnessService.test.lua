--!strict
--[[
	Class: WitnessService.test
	Description: Unit tests for the Witnessing loop mechanic
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local WitnessService = require(ServerScriptService.Server.services.WitnessService)
local PlayerData = require(ReplicatedStorage.Shared.types.PlayerData)

return function(describe: any, expect: any, it: any)
	describe("WitnessService", function()
		it("initializes and exports testable module", function()
			expect(WitnessService).to.be.ok()
			expect(WitnessService._TickWitnessing).to.be.a("function")
			expect(WitnessService._ResetTracking).to.be.a("function")
		end)
	end)
end

