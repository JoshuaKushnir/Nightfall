--!strict
--[[
	Class: TickManager
	Description: Centralized tick loop for all periodic combat/status effects.
				 Replaces per-target task.spawn() while-loops with a single
				 predictable Heartbeat/Stepped loop.
	Dependencies: RunService
]]

local RunService = game:GetService("RunService")
local TickManager = {}

-- Store registered tick functions by string key
local _tickHandlers: { [string]: (number, number) -> () } = {}

-- Connection
local _connection: RBXScriptConnection? = nil

--[[
	Initialize the TickManager
]]
function TickManager:Start()
	if _connection then return end

	_connection = RunService.Heartbeat:Connect(function(dt)
		self:_OnHeartbeat(dt)
	end)
end

--[[
	Register a handler function that runs every frame
	@param id Unique identifier
	@param handler Function to run
]]
function TickManager:RegisterHandler(id: string, handler: (number, number) -> ())
	_tickHandlers[id] = handler
end

--[[
	Unregister a handler
	@param id Unique identifier
]]
function TickManager:UnregisterHandler(id: string)
	_tickHandlers[id] = nil
end

--[[
	Internal: Main loop
]]
function TickManager:_OnHeartbeat(dt: number)
	local now = tick()

	-- Run standard frame handlers
	for _, handler in _tickHandlers do
		handler(dt, now)
	end
end

return TickManager
