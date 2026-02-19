--!strict
-- MovementService.lua
-- Server-side validation for client movement requests (slides/slide-jumps)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

local MovementService = {}

local NetworkService: any = nil

-- Track last slide time per player to enforce server-side cooldowns
local lastSlideTime: {[Player]: number} = {}

function MovementService:Init(dependencies: {[string]: any}?)
	NetworkService = (dependencies and dependencies.NetworkService) or nil
	if not NetworkService then
		error("[MovementService] NetworkService dependency required")
	end
	print("[MovementService] Initialized")
end

local function validateSlideRequest(player: Player, packet: any): (boolean, string?)
	if type(packet) ~= "table" or (packet.Type ~= "Start" and packet.Type ~= "Leap") then
		return false, "malformed_packet"
	end

	local pd = StateService:GetPlayerData(player)
	if not pd then
		return false, "no_player_data"
	end

	-- Only allow sliding when player is running (server-side guard)
	if pd.State ~= "Running" then
		return false, "invalid_state"
	end

	local cooldown = (MovementConfig.Dodge and MovementConfig.Dodge.Cooldown) or 1.5
	local last = lastSlideTime[player] or 0
	if tick() - last < cooldown then
		return false, "cooldown"
	end

	return true, nil
end

function MovementService:Start()
	if not NetworkService then return end

	NetworkService:RegisterHandler("RequestSlide", function(player: Player, packet: any)
		local ok, reason = validateSlideRequest(player, packet)
		if not ok then
			print(('[MovementService] Reject slide from %s — %s'):format(player.Name, tostring(reason)))
			-- Notify client for debugging / corrective action
			NetworkService:SendToClient(player, "DebugInfo", { Category = "Movement", Data = { Error = reason } })
			return
		end

		-- Accept: record timestamp for cooldown enforcement
		lastSlideTime[player] = tick()
		print(('[MovementService] Slide accepted for %s (type=%s)'):format(player.Name, tostring(packet.Type)))
	end)

	print("[MovementService] Started — slide requests will be validated")
end

-- Cleanup on player leave (optional)
game.Players.PlayerRemoving:Connect(function(player)
	lastSlideTime[player] = nil
end)

return MovementService