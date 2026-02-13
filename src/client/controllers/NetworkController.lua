--!strict
--[[
	NetworkController - Client-side network communication handler
	
	Issue #4: Centralized Network Communication Provider
	Epic: Phase 1 - Core Framework
	
	This controller handles all network communication from the client side.
	It provides type-safe event firing, response handling, and connection retry logic.
	
	Features:
	- Type-safe event firing to server
	- Server event listening with handlers
	- Promise-based request/response pattern (future)
	- Connection retry logic
	- Event queuing for offline periods
	
	Usage (Client):
		NetworkController:Init()
		NetworkController:Start()
		
		-- Send event to server
		NetworkController:SendToServer("MantraCast", {
			MantraId = "FireBlast",
			TargetPosition = Vector3.new(0, 10, 0),
		})
		
		-- Listen for server events
		NetworkController:RegisterHandler("DamageDealt", function(packet)
			print(`Took damage: {packet.Damage}`)
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

-- Controller state
local NetworkController = {}
NetworkController._initialized = false
NetworkController._handlers = {} :: {[NetworkEvent]: {(packet: any) -> ()}}
NetworkController._eventQueue = {} :: {{EventName: NetworkEvent, Packet: any}}
NetworkController._isConnected = true

-- Constants
local MAX_QUEUE_SIZE = 100
local RECONNECT_RETRY_DELAY = 5 -- seconds

--[[
	Initialize NetworkController
	Sets up NetworkProvider and prepares to send/receive events
]]
function NetworkController:Init(dependencies)
	if self._initialized then
		warn("[NetworkController] Already initialized")
		return
	end
	
	print("[NetworkController] Initializing...")
	
	-- Wait for player
	local player = Players.LocalPlayer
	if not player then
		error("[NetworkController] LocalPlayer not found")
	end
	
	-- Initialize NetworkProvider (client-side)
	NetworkProvider:Init()
	
	self._initialized = true
	print("[NetworkController] Initialized successfully")
end

--[[
	Start NetworkController
	Begins listening to network events from server
]]
function NetworkController:Start()
	if not self._initialized then
		error("[NetworkController] Must call Init() before Start()")
	end
	
	print("[NetworkController] Starting...")
	
	-- Connect to all registered network events for client listening
	local allEvents = NetworkProvider:GetAllEvents()
	
	for _, eventName in allEvents do
		local metadata = NetworkProvider:GetEventMetadata(eventName)
		
		if not metadata then
			continue
		end
		
		-- Only listen to events that server can send
		if metadata.Direction == "ClientToServer" then
			continue
		end
		
		local remote = NetworkProvider:GetRemoteEvent(eventName)
		
		if not remote then
			warn(`[NetworkController] RemoteEvent not found: {eventName}`)
			continue
		end
		
		-- Connect to event
		remote.OnClientEvent:Connect(function(packet: any)
			self:_HandleEvent(eventName, packet)
		end)
		
		print(`[NetworkController] Listening to event: {eventName}`)
	end
	
	-- Process queued events
	self:_ProcessEventQueue()
	
	print("[NetworkController] Started successfully")
end

--[[
	Internal: Handle incoming network event from server
	@private
]]
function NetworkController:_HandleEvent(eventName: NetworkEvent, packet: any)
	local handlers = self._handlers[eventName]
	
	if not handlers or #handlers == 0 then
		-- No handlers registered, that's okay for some events
		return
	end
	
	-- Execute all handlers
	for _, handler in handlers do
		task.spawn(function()
			local success, err = pcall(handler, packet)
			
			if not success then
				warn(`[NetworkController] Handler error for {eventName}: {err}`)
			end
		end)
	end
end

--[[
	Internal: Process queued events that were sent while offline
	@private
]]
function NetworkController:_ProcessEventQueue()
	if #self._eventQueue == 0 then
		return
	end
	
	print(`[NetworkController] Processing {#self._eventQueue} queued events`)
	
	for _, queuedEvent in self._eventQueue do
		self:SendToServer(queuedEvent.EventName, queuedEvent.Packet)
	end
	
	-- Clear queue
	table.clear(self._eventQueue)
end

--[[
	Register a handler for a network event from the server
	
	@param eventName - The network event to listen for
	@param handler - The function to call when the event fires
]]
function NetworkController:RegisterHandler(eventName: NetworkEvent, handler: (packet: any) -> ())
	if not self._handlers[eventName] then
		self._handlers[eventName] = {}
	end
	
	table.insert(self._handlers[eventName], handler)
	print(`[NetworkController] Registered handler for event: {eventName}`)
end

--[[
	Send an event to the server
	
	@param eventName - The network event to fire
	@param packet - The data to send
]]
function NetworkController:SendToServer(eventName: NetworkEvent, packet: NetworkPacket)
	if not self._initialized then
		warn("[NetworkController] Not initialized - cannot send event")
		return
	end
	
	local remote = NetworkProvider:GetRemoteEvent(eventName)
	
	if not remote then
		warn(`[NetworkController] Cannot send event {eventName}: RemoteEvent not found`)
		return
	end
	
	-- Check connection
	if not self._isConnected then
		-- Queue event for later
		if #self._eventQueue < MAX_QUEUE_SIZE then
			table.insert(self._eventQueue, {
				EventName = eventName,
				Packet = packet,
			})
			warn(`[NetworkController] Connection lost - queued event: {eventName}`)
		else
			warn(`[NetworkController] Event queue full - dropped event: {eventName}`)
		end
		return
	end
	
	-- Send to server
	local success, err = pcall(function()
		remote:FireServer(packet)
	end)
	
	if not success then
		warn(`[NetworkController] Failed to send event {eventName}: {err}`)
		self._isConnected = false
		
		-- Attempt reconnection
		task.delay(RECONNECT_RETRY_DELAY, function()
			self._isConnected = true
			self:_ProcessEventQueue()
		end)
	end
end

--[[
	Check if the controller is connected to the server
	
	@return boolean - True if connected, false otherwise
]]
function NetworkController:IsConnected(): boolean
	return self._isConnected
end

--[[
	Get the number of queued events
	
	@return number - The queue size
]]
function NetworkController:GetQueueSize(): number
	return #self._eventQueue
end

return NetworkController
