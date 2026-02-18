--!strict
-- DummyService unit tests

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DummyService = require(ReplicatedStorage.Server.services.DummyService)

return {
	name = "DummyService Unit Tests",
	tests = {
		{
			name = "SpawnDummy creates dummy data and model",
			fn = function()
				local pos = Vector3.new(0, 5, 0)
				local id = DummyService.SpawnDummy(pos)
				assert(type(id) == "string")

				local data = DummyService.GetDummyData(id)
				assert(data ~= nil)
				assert(data.Position == pos)

				local model = Workspace:FindFirstChild(`Dummy_{id}`)
				assert(model ~= nil)

				-- Cleanup
				DummyService.DespawnDummy(id)
			end,
		},
		{
			name = "ApplyDamage reduces health and despawns on death",
			fn = function()
				local id = DummyService.SpawnDummy(Vector3.new(0, 5, 0))
				local data = DummyService.GetDummyData(id)
				assert(data ~= nil)
				assert(data.Health == data.MaxHealth)

				local alive = DummyService.ApplyDamage(id, data.MaxHealth - 10)
				assert(alive == true)
				assert(DummyService.GetDummyData(id).Health == 10)

				local alive2 = DummyService.ApplyDamage(id, 20)
				assert(alive2 == false)
				assert(DummyService.GetDummyData(id) == nil)
			end,
		},
		{
			name = "DespawnDummy removes model and data",
			fn = function()
				local id = DummyService.SpawnDummy(Vector3.new(0, 5, 0))
				DummyService.DespawnDummy(id)
				assert(DummyService.GetDummyData(id) == nil)
				assert(Workspace:FindFirstChild(`Dummy_{id}`) == nil)
			end,
		},
	},
}
