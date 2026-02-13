--!strict
--[[
	ClientInit.client.lua (LocalScript)
	
	Issue #41: Runtime Bootstrap Scripts Missing
	Epic: Phase 1 - Core Framework
	
	This LocalScript is executed automatically by Roblox when the player joins.
	It requires the runtime module which bootstraps all controllers.
	
	Note: This MUST be a LocalScript (not ModuleScript) for Roblox to execute it.
	The .client.lua suffix ensures it only runs on the client.
]]

-- Require the runtime bootstrap module
-- This will load all controllers and initialize them
require(script.Parent.runtime.init)

print("[ClientInit] Bootstrap initiated - see runtime output above")
