--!strict
--[[
	DebugSettings.lua
	
	Debug and development settings that can be toggled at runtime.
	Provides a central place for all debug flags.
	
	Public API:
	- Toggle(settingName) - Toggle a setting on/off
	- Set(settingName, value) - Set a setting to a value
	- Get(settingName) - Get current value of setting
	- GetAll() - Get all settings
	
	Settings:
	- ShowHitboxes: Visualize collision boxes in 3D space
	- ShowStateLabels: Display player state above characters
	- ShowNetworkEvents: Log all network events
	- SlowMotion: Slow down game time for debugging
]]

local DebugSettings = {}

-- Settings storage
local Settings: {[string]: boolean | number | string} = {
	ShowHitboxes = true,
	ShowStateLabels = false,
	ShowNetworkEvents = false,
	SlowMotion = false,
	SlowMotionSpeed = 0.5,
}

-- Change signals for reactive systems
local SettingChanged = {}

--[[
	Toggle a boolean setting
	@param settingName Name of the setting
	@return New value
]]
function DebugSettings.Toggle(settingName: string): any
	if Settings[settingName] == nil then
		warn(`[DebugSettings] Unknown setting: {settingName}`)
		return nil
	end
	
	local currentType = type(Settings[settingName])
	
	-- Only toggle booleans
	if currentType == "boolean" then
		Settings[settingName] = not (Settings[settingName] :: boolean)
		DebugSettings._NotifyChange(settingName, Settings[settingName])
		print(`[DebugSettings] {settingName} = {Settings[settingName]}`)
	else
		warn(`[DebugSettings] Cannot toggle non-boolean setting: {settingName}`)
	end
	
	return Settings[settingName]
end

--[[
	Set a setting to a specific value
	@param settingName Name of the setting
	@param value New value
	@return New value
]]
function DebugSettings.Set(settingName: string, value: any): any
	if Settings[settingName] == nil then
		warn(`[DebugSettings] Unknown setting: {settingName}`)
		return nil
	end
	
	Settings[settingName] = value
	DebugSettings._NotifyChange(settingName, value)
	print(`[DebugSettings] {settingName} = {value}`)
	
	return value
end

--[[
	Get a setting value
	@param settingName Name of the setting
	@return Current value or nil
]]
function DebugSettings.Get(settingName: string): any
	return Settings[settingName]
end

--[[
	Get all settings
	@return Table of all settings
]]
function DebugSettings.GetAll(): {[string]: any}
	local copy: {[string]: any} = {}
	for key, value in Settings do
		copy[key] = value
	end
	return copy
end

--[[
	Register a callback for when a setting changes
	@param settingName Name of setting to watch
	@param callback Function to call when setting changes
	@return Disconnect function
]]
function DebugSettings.OnChanged(settingName: string, callback: (string, any) -> ()): () -> ()
	if not SettingChanged[settingName] then
		SettingChanged[settingName] = {}
	end
	
	table.insert(SettingChanged[settingName], callback)
	
	-- Return disconnect function
	return function()
		local callbacks = SettingChanged[settingName]
		if callbacks then
			local index = table.find(callbacks, callback)
			if index then
				table.remove(callbacks, index)
			end
		end
	end
end

--[[
	Internal: Notify all listeners of a setting change
]]
function DebugSettings._NotifyChange(settingName: string, newValue: any)
	local callbacks = SettingChanged[settingName]
	if callbacks then
		for _, callback in callbacks do
			task.spawn(callback, settingName, newValue)
		end
	end
end

--[[
	List all available settings and their values
]]
function DebugSettings.ListSettings()
	print("[DebugSettings] Available settings:")
	for name, value in Settings do
		local valueStr = if type(value) == "boolean" then (if value then "✓" else "✗") else tostring(value)
		print(`  {name}: {valueStr}`)
	end
end

return DebugSettings
