--!strict
--[[
	ServerInit.server.lua (Script)
	
	Issue #41: Runtime Bootstrap Scripts Missing
	Epic: Phase 1 - Core Framework
	
	This Script is executed automatically by Roblox when the server starts.
	It requires the runtime module which bootstraps all services.
	
	Note: This MUST be a Script (not ModuleScript) for Roblox to execute it.
	The .server.lua suffix ensures it only runs on the server.
]]

-- Require the runtime bootstrap module
-- This will load all services and initialize them
require(script.Parent.runtime)

print("[ServerInit] Bootstrap initiated - see runtime output above")
