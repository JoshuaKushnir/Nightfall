--!strict
--[[
	NetworkService - Server-side network event handler
	
	Issue #4: Centralized Network Communication Provider  
	Epic: Phase 1 - Core Framework
	
	This service handles all incoming network events from clients.
	It provides rate limiting, validation, and middleware support.
	
	Features:
	- Rate limiting per player per event
	- Validation middleware (authentication, authorization, sanitization)
	- Suspicious activity logging
	- Type-safe event handlers
	- Easy event registration
	
	Usage:
		NetworkService:Init()
		NetworkService:Start()
		
		NetworkService:RegisterHandler("MantraCast", function(player, packet)
			-- Handle mantra cast request
			print(`{player.Name} cast mantra: {packet.MantraId}`)
		end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Dependencies
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local NetworkTypes = require(ReplicatedStorage.Shared.types.NetworkTypes)

type NetworkEvent = NetworkTypes.NetworkEvent
type EventMetadata = NetworkTypes.EventMetadata
type NetworkPacket = NetworkTypes.NetworkPacket

-- Service state
local NetworkService = {}
NetworkService._initialized = false
NetworkService._handlers = {} :: {[NetworkEvent]: {(player: Player, packet: any) -> ()}}
NetworkService._middleware = {} :: {(player: Player, eventName: NetworkEvent, packet: any) -> boolean}

-- Rate limiting tracking
type RateLimitData = {
	Count: number,
	LastReset: number,
}

local RateLimits: {[Player]: {[NetworkEvent]: RateLimitData}} = {}

-- Constants
local RATE_LIMIT_WINDOW = 1 -- seconds
local MAX_WARNINGS_BEFORE_KICK = 10
local PlayerWarnings: {[Player]: number} = {}

-- Private: Check rate limit
local function CheckRateLimit(player: Player, eventName: NetworkEvent, metadata: EventMetadata): boolean
	local limit = metadata.RateLimitPerSecond
	
	if not limit then
		return true -- No rate limit
	end
	
	-- Initialize tracking
	if not RateLimits[player] then
		RateLimits[player] = {}
	end
	
	local now = os.clock()
	local eventLimits = RateLimits[player][eventName]
	
	if not eventLimits then
		RateLimits[player][eventName] = {
			Count = 1,
			LastReset = now,
		}
		return true
	end
	
	-- Reset window if needed
	if now - eventLimits.LastReset >= RATE_LIMIT_WINDOW then
		eventLimits.Count = 1
		eventLimits.LastReset = now
		return true
	end
	
	-- Check limit
	if eventLimits.Count >= limit then
		-- Rate limit exceeded
		warn(`[NetworkService] Rate limit exceeded for {player.Name} on event: {eventName} ({eventLimits.Count}/{limit})`)
		
		NetworkService:_RecordSuspiciousActivity(player, `Rate limit exceeded: {eventName}`)
		return false
	end
	
	-- Increment count
	eventLimits.Count += 1
	return true
end

-- Private: Run validation middleware
local function RunMiddleware(player: Player, eventName: NetworkEvent, packet: any): boolean
	for _, middleware in NetworkService._middleware do
		local success, result = pcall(middleware, player, eventName, packet)
		
		if not success then
			warn(`[NetworkService] Middleware error for {player.Name}: {result}`)
			return false
		end
		
		if not result then
			-- Middleware rejected the packet
			return false
		end
	end
	
	return true
end

--[[
	Initialize NetworkService
	Sets up NetworkProvider and prepares to handle events
]]
function NetworkService:Init()
	if self._initialized then
		warn("[NetworkService] Already initialized")
		return
	end
	
	print("[NetworkService] Initializing...")
	
	-- Initialize NetworkProvider (creates RemoteEvents)
	NetworkProvider:Init()
	
	-- Add default middleware
	self:AddMiddleware(function(player: Player, eventName: NetworkEvent, packet: any): boolean
		-- Authentication: Verify player instance is valid
		if not player or not player.Parent == Players then
			warn(`[NetworkService] Invalid player instance for event: {eventName}`)
			return false
		end
		
		return true
	end)
	
	self._initialized = true
	print("[NetworkService] Initialized successfully")
end

--[[
	Start NetworkService
	Begins listening to network events from clients
]]
function NetworkService:Start()
	if not self._initialized then
		error("[NetworkService] Must call Init() before Start()")
	end
	
	print("[NetworkService] Starting...")
	
	-- Connect to all registered network events
	local allEvents = NetworkProvider:GetAllEvents()
	
	for _, eventName in allEvents do
		local metadata = NetworkProvider:GetEventMetadata(eventName)
		
		if not metadata then
			continue
		end
		
		-- Only listen to events that clients can send
		if metadata.Direction == "ServerToClient" then
			continue
		end
		
		local remote = NetworkProvider:GetRemoteEvent(eventName)
		
		if not remote then
			warn(`[NetworkService] RemoteEvent not found: {eventName}`)
			continue
		end
		
		-- Connect to event
		remote.OnServerEvent:Connect(function(player: Player, packet: any)
			self:_HandleEvent(player, eventName, packet, metadata)
		end)
		
		print(`[NetworkService] Listening to event: {eventName}`)
	end
	
	-- Cleanup rate limits on player leave
	Players.PlayerRemoving:Connect(function(player)
		RateLimits[player] = nil
		PlayerWarnings[player] = nil
	end)
	
	print("[NetworkService] Started successfully")
end

--[[
	Internal: Handle incoming network event
	@private
]]
function NetworkService:_HandleEvent(player: Player, eventName: NetworkEvent, packet: any, metadata: EventMetadata)
	-- Rate limiting
	if not CheckRateLimit(player, eventName, metadata) then
		return
	end
	
	-- Validation middleware
	if metadata.RequiresValidation then
		if not RunMiddleware(player, eventName, packet) then
			warn(`[NetworkService] Middleware rejected packet from {player.Name} for event: {eventName}`)
			self:_RecordSuspiciousActivity(player, `Validation failed: {eventName}`)
			return
		end
	end
	
	-- Call registered handlers
	local handlers = self._handlers[eventName]
	
	if not handlers or #handlers == 0 then
		warn(`[NetworkService] No handlers registered for event: {eventName}`)
		return
	end
	
	-- Execute all handlers
	for _, handler in handlers do
		task.spawn(function()
			local success, err = pcall(handler, player, packet)
			
			if not success then
				warn(`[NetworkService] Handler error for {player.Name} on {eventName}: {err}`)
			end
		end)
	end
end

--[[
	Internal: Record suspicious activity
	@private
]]
function NetworkService:_RecordSuspiciousActivity(player: Player, reason: string)
	PlayerWarnings[player] = (PlayerWarnings[player] or 0) + 1
	
	local warnings = PlayerWarnings[player]
	
	warn(`[NetworkService] Suspicious activity from {player.Name}: {reason} ({warnings}/{MAX_WARNINGS_BEFORE_KICK} warnings)`)
	
	if warnings >= MAX_WARNINGS_BEFORE_KICK then
		player:Kick(`Suspicious network activity detected. Reason: {reason}`)
	end
end

--[[
	Register a handler for a network event
	
	@param eventName - The network event to listen for
	@param handler - The function to call when the event fires
]]
function NetworkService:RegisterHandler(eventName: NetworkEvent, handler: (player: Player, packet: any) -> ())
	if not self._handlers[eventName] then
		self._handlers[eventName] = {}
	end
	
	table.insert(self._handlers[eventName], handler)
	print(`[NetworkService] Registered handler for event: {eventName}`)
end

--[[
	Add validation middleware
	Middleware runs before handlers and can reject packets
	
	@param middleware - Function that returns true to allow packet, false to reject
]]
function NetworkService:AddMiddleware(middleware: (player: Player, eventName: NetworkEvent, packet: any) -> boolean)
	table.insert(self._middleware, middleware)
	print(`[NetworkService] Added middleware (total: {#self._middleware})`)
end

--[[
	Send an event to a specific client
	
	@param player - The player to send to
	@param eventName - The network event to fire
	@param packet - The data to send
]]
function NetworkService:SendToClient(player: Player, eventName: NetworkEvent, packet: NetworkPacket)
	local remote = NetworkProvider:GetRemoteEvent(eventName)
	
	if not remote then
		warn(`[NetworkService] Cannot send event {eventName}: RemoteEvent not found`)
		return
	end
	
	remote:FireClient(player, packet)
end

--[[
	Send an event to all clients
	
	@param eventName - The network event to fire
	@param packet - The data to send
]]
function NetworkService:SendToAllClients(eventName: NetworkEvent, packet: NetworkPacket)
	local remote = NetworkProvider:GetRemoteEvent(eventName)
	
	if not remote then
		warn(`[NetworkService] Cannot send event {eventName}: RemoteEvent not found`)
		return
	end
	
	remote:FireAllClients(packet)
end

--[[
	Send an event to all clients except one
	
	@param excludePlayer - The player to exclude
	@param eventName - The network event to fire
	@param packet - The data to send
]]
function NetworkService:SendToAllExcept(excludePlayer: Player, eventName: NetworkEvent, packet: NetworkPacket)
	for _, player in Players:GetPlayers() do
		if player ~= excludePlayer then
			self:SendToClient(player, eventName, packet)
		end
	end
end

return NetworkService
