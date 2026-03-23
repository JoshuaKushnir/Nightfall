--!strict
--[[
	RunMode.lua

	Defines the current execution environment mode for the game.
	Used to gate debug features, logging, and other development tools.
]]

local RunService = game:GetService("RunService")

export type RunModeType = "dev" | "staging" | "production"

local RunMode = {}

-- Determine the default run mode based on the environment
local function determineMode(): RunModeType
	if RunService:IsStudio() then
		return "dev"
	end

	-- In a real game, you might check game.PlaceId or a specific Datastore key
	-- For now, if not in studio, assume production
	return "production"
end

local currentMode: RunModeType = determineMode()

--[[
	Get the current run mode
	@return "dev" | "staging" | "production"
]]
function RunMode.Get(): RunModeType
	return currentMode
end

--[[
	Check if the current mode is development
	@return true if in "dev" mode
]]
function RunMode.IsDev(): boolean
	return currentMode == "dev"
end

--[[
	Check if the current mode is production
	@return true if in "production" mode
]]
function RunMode.IsProduction(): boolean
	return currentMode == "production"
end

--[[
	Force override the run mode (typically only used via secure admin commands)
	@param mode New mode to set
]]
function RunMode.SetOverride(mode: RunModeType)
	currentMode = mode
end

return RunMode
