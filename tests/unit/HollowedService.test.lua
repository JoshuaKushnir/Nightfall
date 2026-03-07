--!strict
-- HollowedService unit tests
-- Issue #143: Ring 1 patrol/aggro/attack AI, death + Resonance grant

local Workspace = game:GetService("Workspace")

-- Stub dependencies before loading the service
local mockProgressionGrantCalls: {{player: any, amount: number, source: string}} = {}
local mockProgressionService = {
	GrantResonance = function(player: any, amount: number, source: string)
		table.insert(mockProgressionGrantCalls, { player = player, amount = amount, source = source })
	end,
}

local mockPostureService = {
	DrainPosture = function(_player: any, _amount: number, _source: string) end,
}

local HollowedService = require(game:GetService("ReplicatedStorage").Server.services.HollowedService)

-- Inject mocks via Init
HollowedService:Init({
	ProgressionService = mockProgressionService,
	PostureService     = mockPostureService,
})

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function spawnAt(x: number): string
	local id = HollowedService.SpawnInstance("basic_hollowed", CFrame.new(x, 5, 0))
	assert(id ~= nil, "SpawnInstance returned nil")
	return id :: string
end

local function cleanup(id: string)
	HollowedService.DespawnInstance(id)
end

local function resetGrantLog()
	table.clear(mockProgressionGrantCalls)
end

-- ─── Tests ───────────────────────────────────────────────────────────────────

return {
	name = "HollowedService Unit Tests",
	tests = {
		-- ── Spawn ────────────────────────────────────────────────────────────

		{
			name = "SpawnInstance creates data with Patrol state and full HP",
			fn = function()
				local id = spawnAt(0)
				local data = HollowedService.GetInstanceData(id)
				assert(data ~= nil, "expected instance data")
				assert(data.State == "Patrol", "expected Patrol state, got " .. data.State)
				assert(data.CurrentHealth == data.MaxHealth, "expected full HP")
				assert(data.IsActive == true, "expected IsActive")
				cleanup(id)
			end,
		},

		{
			name = "SpawnInstance creates Model in Workspace",
			fn = function()
				local id = spawnAt(10)
				local model = Workspace:FindFirstChild(id)
				assert(model ~= nil, "expected model in Workspace named " .. id)
				cleanup(id)
			end,
		},

		{
			name = "SpawnInstance returns nil for unknown configId",
			fn = function()
				local id = HollowedService.SpawnInstance("not_a_real_config", CFrame.new())
				assert(id == nil, "expected nil for invalid configId")
			end,
		},

		-- ── Despawn ──────────────────────────────────────────────────────────

		{
			name = "DespawnInstance removes data and model",
			fn = function()
				local id = spawnAt(20)
				cleanup(id)
				assert(HollowedService.GetInstanceData(id) == nil, "data should be nil after despawn")
				assert(Workspace:FindFirstChild(id) == nil, "model should be gone after despawn")
			end,
		},

		-- ── ApplyDamage — survival ────────────────────────────────────────────

		{
			name = "ApplyDamage reduces health and returns true when alive",
			fn = function()
				local id = spawnAt(30)
				local data = HollowedService.GetInstanceData(id)
				assert(data ~= nil)
				local beforeHp = data.CurrentHealth

				local alive = HollowedService.ApplyDamage(id, 10, nil)
				assert(alive == true, "expected true (still alive)")
				assert(data.CurrentHealth == beforeHp - 10, "HP should decrease by 10")
				cleanup(id)
			end,
		},

		{
			name = "ApplyDamage clamps HP to zero (no negative HP)",
			fn = function()
				local id = spawnAt(40)
				HollowedService.ApplyDamage(id, 9999, nil)
				-- instance may be dead at this point
				local data = HollowedService.GetInstanceData(id)
				if data then
					assert(data.CurrentHealth >= 0, "HP must not go negative")
				end
				cleanup(id)
			end,
		},

		-- ── ApplyDamage — death ───────────────────────────────────────────────

		{
			name = "ApplyDamage returns false and sets state Dead when HP hits 0",
			fn = function()
				local id = spawnAt(50)
				local data = HollowedService.GetInstanceData(id)
				assert(data ~= nil)

				local alive = HollowedService.ApplyDamage(id, data.MaxHealth, nil)
				assert(alive == false, "expected false (dead)")
				assert(data.State == "Dead", "expected Dead state")
				assert(data.IsActive == false, "expected IsActive=false")
				cleanup(id)
			end,
		},

		{
			name = "ApplyDamage grants Resonance to attacker on kill",
			fn = function()
				resetGrantLog()

				local id = spawnAt(60)
				local data = HollowedService.GetInstanceData(id)
				assert(data ~= nil)

				-- Fake attacker player-like object
				local fakePlayer = { UserId = 99999, Name = "TestKiller", Character = nil }
				HollowedService.ApplyDamage(id, data.MaxHealth, fakePlayer :: any)

				assert(#mockProgressionGrantCalls >= 1, "expected GrantResonance to be called")
				local call = mockProgressionGrantCalls[#mockProgressionGrantCalls]
				assert(call.player == fakePlayer, "expected correct player")
				assert(call.amount == 25, ("expected 25 Resonance, got %d"):format(call.amount))
				assert(call.source == "Hollowed", ("expected source 'Hollowed', got '%s'"):format(call.source))
				cleanup(id)
			end,
		},

		{
			name = "ApplyDamage with no attacker does not error (Resonance simply not granted)",
			fn = function()
				resetGrantLog()
				local id = spawnAt(70)
				local data = HollowedService.GetInstanceData(id)
				assert(data ~= nil)
				local ok, err = pcall(HollowedService.ApplyDamage, id, data.MaxHealth, nil)
				assert(ok, "expected no error when attacker is nil: " .. tostring(err))
				assert(#mockProgressionGrantCalls == 0, "should not grant Resonance with nil attacker")
				cleanup(id)
			end,
		},

		{
			name = "ApplyDamage on already-dead instance returns false",
			fn = function()
				local id = spawnAt(80)
				local data = HollowedService.GetInstanceData(id)
				assert(data ~= nil)
				HollowedService.ApplyDamage(id, data.MaxHealth, nil)  -- kill
				-- attempt second hit while dead
				local result = HollowedService.ApplyDamage(id, 5, nil)
				assert(result == false, "dead NPC should return false")
				cleanup(id)
			end,
		},

		-- ── GetInstanceData ───────────────────────────────────────────────────

		{
			name = "GetInstanceData returns nil for unknown instanceId",
			fn = function()
				local data = HollowedService.GetInstanceData("Hollowed_999999")
				assert(data == nil, "expected nil for unknown id")
			end,
		},

		-- ── Multiple instances ────────────────────────────────────────────────

		{
			name = "Multiple instances are independent — damage on one does not affect others",
			fn = function()
				local idA = spawnAt(100)
				local idB = spawnAt(110)
				local dataA = HollowedService.GetInstanceData(idA)
				local dataB = HollowedService.GetInstanceData(idB)
				assert(dataA and dataB)

				HollowedService.ApplyDamage(idA, 20, nil)
				assert(dataB.CurrentHealth == dataB.MaxHealth, "instance B should be undamaged")

				cleanup(idA)
				cleanup(idB)
			end,
		},
	},
}
