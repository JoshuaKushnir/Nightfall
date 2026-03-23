--!strict
-- Class: DebugSettings
-- Description: Debug and development settings that can be toggled at runtime. Gated behind RunMode to prevent debug features from leaking into production.
-- Dependencies: RunMode

local RunMode = require(script.Parent.RunMode)

local DebugSettings = {}

-- Settings storage
local Settings: {[string]: boolean | number | string} = {
	ShowHitboxes = false,
	ShowStateLabels = false,
	ShowNetworkEvents = false,
	SlowMotion = false,
	SlowMotionSpeed = 0.5,
}

-- If in dev mode, enable some by default
if RunMode.IsDev() then
	Settings.ShowHitboxes = true
end

-- Change signals for reactive systems
local SettingChanged = {}

--[[
	Toggle a boolean setting. Returns false and warns if in production.
	@param settingName Name of the setting
	@return New value
]]
function DebugSettings.Toggle(settingName: string): any
	if RunMode.IsProduction() then
		return false
	end

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
	Set a setting to a specific value. Prevented in production mode for debug flags.
	@param settingName Name of the setting
	@param value New value
	@return New value
]]
function DebugSettings.Set(settingName: string, value: any): any
	if RunMode.IsProduction() then
		return Settings[settingName]
	end

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
	Get a setting value. In production, boolean debug flags are forced to false.
	@param settingName Name of the setting
	@return Current value or nil
]]
function DebugSettings.Get(settingName: string): any
	if RunMode.IsProduction() and type(Settings[settingName]) == "boolean" then
		return false
	end
	return Settings[settingName]
end

--[[
	Get all settings
	@return Table of all settings
]]
function DebugSettings.GetAll(): {[string]: any}
	local copy: {[string]: any} = {}
	local isProd = RunMode.IsProduction()

	for key, value in Settings do
		if isProd and type(value) == "boolean" then
			copy[key] = false
		else
			copy[key] = value
		end
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
	local all = DebugSettings.GetAll()
	for name, value in all do
		local valueStr = if type(value) == "boolean" then (if value then "✓" else "✗") else tostring(value)
		print(`  {name}: {valueStr}`)
	end
end

return DebugSettings
