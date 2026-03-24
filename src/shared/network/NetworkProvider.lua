--!strict
--[[
	NetworkProvider - Central registry for network RemoteEvents and RemoteFunctions

	Issue #4: Centralized Network Communication Provider
	Epic: Phase 1 - Core Framework

	This module creates and manages all RemoteEvent/RemoteFunction instances
	for client-server communication. It provides a type-safe interface for
	network operations.

	Architecture:
	- Server: NetworkService listens to events from clients
	- Client: NetworkController sends events to server and listens for responses
	- Shared: NetworkProvider creates and provides access to RemoteEvents/Functions

	Usage (Shared):
		local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
		local remote = NetworkProvider:GetRemoteEvent("AbilityCastRequest")

	Usage (Server):
		remote.OnServerEvent:Connect(function(player, packet)
			-- Handle client request
		end)

	Usage (Client):
		remote:FireServer(packet)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Import types
local NetworkTypes = require(ReplicatedStorage.Shared.types.NetworkTypes)
type NetworkEvent = NetworkTypes.NetworkEvent
type EventMetadata = NetworkTypes.EventMetadata

-- Network Provider
local NetworkProvider = {}
NetworkProvider._initialized = false
NetworkProvider._remoteEvents = {} :: {[NetworkEvent]: RemoteEvent}
NetworkProvider._remoteFunctions = {} :: {[NetworkEvent]: RemoteFunction}
NetworkProvider._networkFolder = nil :: Folder?

-- Constants
local NETWORK_FOLDER_NAME = "NetworkEvents"

--[[
	Initialize the NetworkProvider
	Creates the network folder and all RemoteEvents/RemoteFunctions

	Should be called once on server startup before any other services
]]
function NetworkProvider:Init()
	if self._initialized then
		warn("[NetworkProvider] Already initialized")
		return
	end

	print("[NetworkProvider] Initializing...")

	-- Find or create network folder
	local networkFolder = ReplicatedStorage:FindFirstChild(NETWORK_FOLDER_NAME)
	local allEvents = NetworkTypes.GetAllEvents()

	if RunService:IsServer() then
		-- Server creates the folder and remotes
		if not networkFolder then
			networkFolder = Instance.new("Folder")
			networkFolder.Name = NETWORK_FOLDER_NAME
			networkFolder.Parent = ReplicatedStorage
			print(`[NetworkProvider] Created network folder: {NETWORK_FOLDER_NAME}`)
		end

		-- Create RemoteEvents for all registered events
		for _, eventName in allEvents do
			local metadata = NetworkTypes.GetEventMetadata(eventName)

			if not metadata then
				warn(`[NetworkProvider] No metadata found for event: {eventName}`)
				continue
			end

			-- Create RemoteEvent (most common)
			local remote = networkFolder:FindFirstChild(eventName) :: RemoteEvent?

			if not remote then
				remote = Instance.new("RemoteEvent")
				remote.Name = eventName
				remote.Parent = networkFolder
				print(`[NetworkProvider] Created RemoteEvent: {eventName}`)
			end

			self._remoteEvents[eventName] = remote
		end

		print(`[NetworkProvider] Created {#allEvents} RemoteEvents`)

	else
		-- Client waits for folder and remotes to be created by server
		if not networkFolder then
			print("[NetworkProvider] Waiting for network folder from server...")
			networkFolder = ReplicatedStorage:WaitForChild(NETWORK_FOLDER_NAME, 10)

			if not networkFolder then
				error("[NetworkProvider] Failed to find network folder from server")
			end
		end

		-- Wait for RemoteEvents to be replicated from server
		-- The folder exists but events may still be replicating
		local expectedEventCount = #allEvents
		local waitStart = os.clock()
		local MAX_WAIT = 5
		local eventCount = 0

		while os.clock() - waitStart < MAX_WAIT do
			-- Cache all RemoteEvents and RemoteFunctions found so far
			table.clear(self._remoteEvents)
			table.clear(self._remoteFunctions)

			for _, child in networkFolder:GetChildren() do
				if child:IsA("RemoteEvent") then
					self._remoteEvents[child.Name] = child
				elseif child:IsA("RemoteFunction") then
					self._remoteFunctions[child.Name] = child
				end
			end

			eventCount = 0
			for _ in self._remoteEvents do
				eventCount += 1
			end

			-- Wait until ALL expected events are found
			if eventCount >= expectedEventCount then
				break
			end

			task.wait(0.05)
		end

		if eventCount < expectedEventCount then
			warn(`[NetworkProvider] Missing RemoteEvents! Found {eventCount} of {expectedEventCount} - network may not function correctly`)
		else
			print(`[NetworkProvider] Found all {eventCount} RemoteEvents from server`)
		end
	end

	self._networkFolder = networkFolder
	self._initialized = true

	print("[NetworkProvider] Initialized successfully")
end

--[[
	Get a RemoteEvent by name

	@param eventName - The name of the network event
	@return RemoteEvent? - The RemoteEvent instance, or nil if not found
]]
function NetworkProvider:GetRemoteEvent(eventName: NetworkEvent): RemoteEvent?
	if not self._initialized then
		error("[NetworkProvider] Not initialized - call Init() first")
	end

	local remote = self._remoteEvents[eventName]

	if not remote then
		warn(`[NetworkProvider] RemoteEvent not found: {eventName}`)
		return nil
	end

	return remote
end

--[[
	Get a RemoteFunction by name

	@param eventName - The name of the network event
	@return RemoteFunction? - The RemoteFunction instance, or nil if not found
]]
function NetworkProvider:GetRemoteFunction(eventName: NetworkEvent): RemoteFunction?
	if not self._initialized then
		error("[NetworkProvider] Not initialized - call Init() first")
	end

	local remote = self._remoteFunctions[eventName]

	if not remote then
		warn(`[NetworkProvider] RemoteFunction not found: {eventName}`)
		return nil
	end

	return remote
end

--[[
	Convenience wrapper for clients: fire a RemoteEvent by name.
	Logs warning if the event does not exist.
]]
function NetworkProvider:FireServer(eventName: NetworkEvent, ...)
	local remote = self:GetRemoteEvent(eventName)
	if remote then
		remote:FireServer(...)
	else
		warn(`[NetworkProvider] FireServer failed, no RemoteEvent: {eventName}`)
	end
end

--[[
	Convenience wrapper for server-to-client traffic. Fires the named
	remote event to a specific player. Logs warning if event missing or
	player argument is nil.
]]
function NetworkProvider:FireClient(eventName: NetworkEvent, player: Player?, ...)
	if not RunService:IsServer() then
		error("NetworkProvider:FireClient may only be called from server")
	end

	local remote = self:GetRemoteEvent(eventName)
	if not remote then
		warn(`[NetworkProvider] FireClient failed, no RemoteEvent: {eventName}`)
		return
	end
	if not player then
		warn("[NetworkProvider] FireClient called without player")
		return
	end
	remote:FireClient(player, ...)
end

--[[
	Get metadata for a network event

	@param eventName - The name of the network event
	@return EventMetadata? - The event's metadata, or nil if not found
]]
function NetworkProvider:GetEventMetadata(eventName: NetworkEvent): EventMetadata?
	return NetworkTypes.GetEventMetadata(eventName)
end

--[[
	Get all registered network events

	@return {NetworkEvent} - Array of all network event names
]]
function NetworkProvider:GetAllEvents(): {NetworkEvent}
	return NetworkTypes.GetAllEvents()
end

--[[
	Check if NetworkProvider is initialized

	@return boolean - True if initialized, false otherwise
]]
function NetworkProvider:IsInitialized(): boolean
	return self._initialized
end

--[[
	Get the network folder instance

	@return Folder? - The network folder, or nil if not initialized
]]
function NetworkProvider:GetNetworkFolder(): Folder?
	return self._networkFolder
end

return NetworkProvider
