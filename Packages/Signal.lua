--!strict
--[[
	Signal - Type-safe event/signal implementation
	
	Based on sleitnick/signal API
	https://github.com/sleitnick/rbxts-signal
	
	Usage:
		local signal = Signal.new()
		local connection = signal:Connect(function(value)
			print("Received:", value)
		end)
		signal:Fire("Hello")
		connection:Disconnect()
]]

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
	GetConnectionCount: (self: Signal<T...>) -> number,
}

type ConnectionInternal = {
	Handler: (...any) -> (),
	Connected: boolean,
	_signal: any,
}

type SignalInternal<T...> = {
	_connections: { ConnectionInternal },
	_isDestroyed: boolean,
}

local ConnectionMethods = {}
ConnectionMethods.__index = ConnectionMethods

function ConnectionMethods:Disconnect()
	if not self.Connected then
		return
	end
	
	self.Connected = false
	
	-- Remove from signal's connection list
	local signal = self._signal
	if signal and signal._connections then
		local index = table.find(signal._connections, self)
		if index then
			table.remove(signal._connections, index)
		end
	end
end

local SignalMethods = {}
SignalMethods.__index = SignalMethods

function SignalMethods:Connect(handler: (...any) -> ()): Connection
	if self._isDestroyed then
		error("[Signal] Cannot connect to destroyed signal", 2)
	end
	
	local connection: ConnectionInternal = {
		Handler = handler,
		Connected = true,
		_signal = self,
	}
	
	setmetatable(connection, ConnectionMethods)
	table.insert(self._connections, connection)
	
	return connection :: any
end

function SignalMethods:Once(handler: (...any) -> ()): Connection
	local connection: Connection = nil :: any
	
	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end
		handler(...)
	end)
	
	return connection
end

function SignalMethods:Wait(): ...any
	if self._isDestroyed then
		error("[Signal] Cannot wait on destroyed signal", 2)
	end
	
	local thread = coroutine.running()
	local connection: Connection = nil :: any
	
	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end
		task.spawn(thread, ...)
	end)
	
	return coroutine.yield()
end

function SignalMethods:Fire(...: any)
	if self._isDestroyed then
		error("[Signal] Cannot fire destroyed signal", 2)
	end
	
	-- Create a snapshot of connections to avoid issues with
	-- connections being added/removed during iteration
	local connections = table.clone(self._connections)
	
	for _, connection in connections do
		if connection.Connected then
			task.spawn(connection.Handler, ...)
		end
	end
end

function SignalMethods:DisconnectAll()
	local connections = table.clone(self._connections)
	
	for _, connection in connections do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	
	table.clear(self._connections)
end

function SignalMethods:Destroy()
	if self._isDestroyed then
		return
	end
	
	self:DisconnectAll()
	self._isDestroyed = true
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

function SignalMethods:GetConnectionCount(): number
	return #self._connections
end

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local self: SignalInternal<T...> = {
		_connections = {},
		_isDestroyed = false,
	}
	
	setmetatable(self, SignalMethods)
	
	return self :: any
end

-- Wrap a RBXScriptSignal to provide consistent API
function Signal.wrap(rbxSignal: RBXScriptSignal): Signal<...any>
	local signal = Signal.new()
	
	rbxSignal:Connect(function(...)
		signal:Fire(...)
	end)
	
	return signal
end

-- Check if object is a Signal
function Signal.is(object: any): boolean
	return type(object) == "table" 
		and getmetatable(object) == SignalMethods
end

return Signal
