
-- Service caching to avoid per-hit require overhead (Optimization #189)
local _services = {}
local function GetService(name)
	if _services[name] ~= nil then return _services[name] end
	local RunService = game:GetService("RunService")
	
	if name == "NetworkProvider" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
	elseif name == "HitboxService" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.modules.combat.HitboxService)
	elseif name == "PostureService" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.combat.PostureService) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "CombatService" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.combat.CombatService) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "DummyService" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.entities.DummyService) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	end
	
	return _services[name]
end
--!strict
--[[
	Regenerate.lua  — Active ability
	Status: Regenerating

	Channels inner resilience to restore health over time.
	Ticks for 5 HP every 1 second for 8 seconds (total: up to 40 HP).
	Won't exceed max health.

	Uses a task-based tick loop; tracks identity with a per-character
	"RegenSession" attribute so that early cancellation is possible.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

local Regenerate = {
	Id          = "Regenerate",
	Type        = "Active",
	Description = "Mend your wounds — restore up to 40 HP over 8 seconds. 25s cooldown.",

	Cooldown    = 25,   -- seconds
	Duration    = 8,    -- seconds (number of ticks)
	TickHeal    = 5,    -- HP per tick
	TickRate    = 1,    -- seconds between ticks
	MaxHealth   = 100,  -- placeholder until DataService exposes max HP
}

--[[
	Called by AbilitySystem when activated.
	Spawns a tick loop that heals the player's data Health each second.
]]
function Regenerate.OnActivate(player: Player, _weapon: any)
	local character = player.Character
	if not character then return end

	-- Session token prevents overlapping regen windows
	local sessionId = tostring(os.clock())
	character:SetAttribute("RegenSession", sessionId)
	character:SetAttribute("StatusEffect", "Regenerating")
	print(("[Regenerate] %s began Regenerate (%.0fs × %d HP/s)"):format(
		player.Name, Regenerate.Duration, Regenerate.TickHeal))

	task.spawn(function()
		for i = 1, Regenerate.Duration do
			task.wait(Regenerate.TickRate)

			-- Bail if session was superseded or player left
			if not player.Parent then break end
			if not character or character:GetAttribute("RegenSession") ~= sessionId then break end

			-- Heal via StateService if available
			local playerData = StateService:GetPlayerData(player)
			if playerData then
				local maxHP = Regenerate.MaxHealth
				local before = playerData.Health
				playerData.Health = math.min(maxHP, before + Regenerate.TickHeal)
				print(("[Regenerate] %s +%d HP (%d→%d)"):format(
					player.Name, Regenerate.TickHeal, before, playerData.Health))
			end
		end

		-- Expire status if still ours
		if character and character:GetAttribute("RegenSession") == sessionId then
			character:SetAttribute("RegenSession", nil)
			if character:GetAttribute("StatusEffect") == "Regenerating" then
				character:SetAttribute("StatusEffect", nil)
			end
			print(("[Regenerate] %s Regenerate expired"):format(player.Name))
		end
	end)
end

function Regenerate.ClientActivate(targetPosition: Vector3?)
    local NetworkProvider = GetService("NetworkProvider")
    local remote = NetworkProvider:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({AbilityId = Regenerate.Id, TargetPosition = targetPosition})
    end
end

return Regenerate
