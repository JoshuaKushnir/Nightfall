--!strict
--[[
	UIBinding.lua
	Reactive binding system for UI elements.
	
	Provides utilities for binding UI elements to game state with automatic updates.
	Handles observable patterns, cleanup, and performance optimization.
	
	Architecture:
	- Bind UI elements to state values
	- Auto-update UI when state changes
	- Manage cleanup when UI is destroyed
	- Batch updates for performance
	
	Usage:
		local UIBinding = require(...)
		
		-- Bind a TextLabel to player health
		UIBinding.BindText(healthLabel, function()
			return "Health: " .. tostring(profile.CurrentHealth)
		end, stateSyncController.GetProfileUpdatedSignal())
		
		-- Bind a Frame's visibility to player state
		UIBinding.BindVisible(castingFrame, function()
			return currentState == "Casting"
		end, stateSyncController.GetStateChangedSignal())
]]

local RunService = game:GetService("RunService")

-- Types
export type Binding = {
	Disconnect: () -> (),
}

export type BindingCallback = () -> any
export type Signal = any -- Generic signal type

-- Active Bindings (for cleanup)
local activeBindings: {[Instance]: {Binding}} = {}

-- Render step batching
local updateQueue: {() -> ()} = {}
local queueActive: boolean = false

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
	Processes queued updates on next render step
]]
local function processUpdateQueue()
	if #updateQueue == 0 then
		queueActive = false
		return
	end
	
	-- Process all queued updates
	for _, updateFunc in updateQueue do
		local success, err = pcall(updateFunc)
		if not success then
			warn("[UIBinding] Update error:", err)
		end
	end
	
	-- Clear queue
	table.clear(updateQueue)
	queueActive = false
end

--[[
	Queues an update to be processed on next render step
]]
local function queueUpdate(updateFunc: () -> ())
	table.insert(updateQueue, updateFunc)
	
	-- Start processing if not already active
	if not queueActive then
		queueActive = true
		RunService.Heartbeat:Once(processUpdateQueue)
	end
end

--[[
	Registers a binding for cleanup
]]
local function registerBinding(instance: Instance, binding: Binding)
	if not activeBindings[instance] then
		activeBindings[instance] = {}
		
		-- Auto-cleanup when instance is destroyed
		instance.Destroying:Once(function()
			local bindings = activeBindings[instance]
			if bindings then
				for _, b in bindings do
					b.Disconnect()
				end
				activeBindings[instance] = nil
			end
		end)
	end
	
	table.insert(activeBindings[instance], binding)
end

--[[
	Creates a generic binding
]]
local function createBinding(
	instance: Instance,
	updateFunc: () -> (),
	signal: Signal?
): Binding
	local connections: {RBXScriptConnection} = {}
	
	-- Initial update
	queueUpdate(updateFunc)
	
	-- Connect to signal if provided
	if signal then
		local connection = signal:Connect(function()
			queueUpdate(updateFunc)
		end)
		table.insert(connections, connection)
	end
	
	local binding = {
		Disconnect = function()
			for _, conn in connections do
				conn:Disconnect()
			end
			table.clear(connections)
		end
	}
	
	registerBinding(instance, binding)
	
	return binding
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local UIBinding = {}

--[[
	Binds a TextLabel/TextButton/TextBox text property to a callback
	
	@param textElement - The UI element with a Text property
	@param callback - Function that returns the text value
	@param signal - Optional signal that triggers updates
	@returns Binding object with Disconnect method
]]
function UIBinding.BindText(
	textElement: TextLabel | TextButton | TextBox,
	callback: BindingCallback,
	signal: Signal?
): Binding
	return createBinding(textElement, function()
		textElement.Text = tostring(callback())
	end, signal)
end

--[[
	Binds a GuiObject visibility to a callback
	
	@param element - The UI element
	@param callback - Function that returns boolean (visible/hidden)
	@param signal - Optional signal that triggers updates
	@returns Binding object with Disconnect method
]]
function UIBinding.BindVisible(
	element: GuiObject,
	callback: BindingCallback,
	signal: Signal?
): Binding
	return createBinding(element, function()
		element.Visible = if callback() then true else false
	end, signal)
end

--[[
	Binds a Frame's BackgroundColor3 to a callback
	
	@param element - The UI element
	@param callback - Function that returns Color3
	@param signal - Optional signal that triggers updates
	@returns Binding object with Disconnect method
]]
function UIBinding.BindColor(
	element: GuiObject,
	callback: BindingCallback,
	signal: Signal?
): Binding
	return createBinding(element, function()
		element.BackgroundColor3 = callback()
	end, signal)
end

--[[
	Binds a UIProgressBar or Frame Size to a callback (for health bars, etc.)
	
	@param element - The UI element to resize
	@param callback - Function that returns a number between 0 and 1
	@param signal - Optional signal that triggers updates
	@returns Binding object with Disconnect method
]]
function UIBinding.BindProgress(
	element: GuiObject,
	callback: BindingCallback,
	signal: Signal?
): Binding
	return createBinding(element, function()
		local progress = math.clamp(callback(), 0, 1)
		element.Size = UDim2.fromScale(progress, element.Size.Y.Scale)
	end, signal)
end

--[[
	Binds any property of a UI element to a callback
	
	@param element - The UI element
	@param propertyName - Name of the property to bind
	@param callback - Function that returns the property value
	@param signal - Optional signal that triggers updates
	@returns Binding object with Disconnect method
]]
function UIBinding.BindProperty(
	element: Instance,
	propertyName: string,
	callback: BindingCallback,
	signal: Signal?
): Binding
	return createBinding(element, function()
		(element :: any)[propertyName] = callback()
	end, signal)
end

--[[
	Binds a callback to a signal without a specific UI element
	Useful for custom update logic
	
	@param callback - Function to call when signal fires
	@param signal - Signal that triggers the callback
	@returns Binding object with Disconnect method
]]
function UIBinding.BindCallback(
	callback: () -> (),
	signal: Signal
): Binding
	local connection = signal:Connect(function()
		queueUpdate(callback)
	end)
	
	return {
		Disconnect = function()
			connection:Disconnect()
		end
	}
end

--[[
	Disconnects all bindings for a specific instance
	
	@param instance - The UI element to clean up
]]
function UIBinding.DisconnectAll(instance: Instance)
	local bindings = activeBindings[instance]
	if bindings then
		for _, binding in bindings do
			binding.Disconnect()
		end
		activeBindings[instance] = nil
	end
end

--[[
	Returns the number of active bindings (for debugging)
]]
function UIBinding.GetActiveBindingCount(): number
	local count = 0
	for _, bindings in activeBindings do
		count += #bindings
	end
	return count
end

return UIBinding
