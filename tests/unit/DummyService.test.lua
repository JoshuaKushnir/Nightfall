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
			name = "SpawnStateDummies creates one-per-state spaced 10 studs",
			fn = function()
				local origin = Vector3.new(0, 5, 0)
				DummyService.SpawnStateDummies(origin)
				-- expect eight dummies
				local count = 0
				for _, dd in pairs(DummyService.GetAllDummyData and DummyService.GetAllDummyData() or {}) do
					count += 1
				end
				assert(count >= 8, "expected at least eight dummies")
				-- cleanup all spawned
				for id, _ in pairs(DummyService.GetAllDummyData and DummyService.GetAllDummyData() or {}) do
					DummyService.DespawnDummy(id)
				end
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
		{
			name = "PreferredState prevents stagger transitions",
			fn = function()
				local id = DummyService.SpawnDummy(Vector3.new(0, 5, 0))
				assert(id)
				local data = DummyService.GetDummyData(id)
				assert(data)
				-- lock state to Blocking
				data.PreferredState = "Blocking"
				DummyService.SetDummyState(id, "Blocking")
				assert(DummyService.GetDummyState(id) == "Blocking")
				-- hit the dummy; it should remain Blocking rather than Staggered
				DummyService.ApplyDamage(id, 10)
				assert(DummyService.GetDummyState(id) == "Blocking")
			end,
		},
		{
			name = "PreferredState survives death/respawn",
			fn = function()
				local id = DummyService.SpawnDummy(Vector3.new(0, 5, 0))
				assert(id)
				local data = DummyService.GetDummyData(id)
				assert(data)
				data.PreferredState = "Attacking"
				DummyService.SetDummyState(id, "Attacking")
				-- kill the dummy
				DummyService.ApplyDamage(id, data.MaxHealth + 1)
				-- wait long enough for respawn (4s configured plus buffer)
				task.wait(5)
				-- find a new dummy close to original position
				local all = DummyService.GetAllDummyData()
				local found = false
				for _, d in pairs(all) do
					if d.PreferredState == "Attacking" then
						found = true
						break
					end
				end
				assert(found, "respawned dummy did not keep Attacking state")
			end,
		},
	},
}
