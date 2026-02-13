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
local success, err = pcall(function()
	require(script.Parent.runtime)
end)

if not success then
	warn("[ClientInit] Failed to load runtime:", err)
	warn("[ClientInit] Debug info:")
	warn("  script.Parent:", script.Parent)
	local runtime = script.Parent:FindFirstChild("runtime")
	if runtime then
		warn("  runtime found:", runtime, "ClassName:", runtime.ClassName)
		local init = runtime:FindFirstChild("init") 
		if init then
			warn("  init found, requiring it directly")
			require(init)
		else
			warn("  No init child found in runtime")
			for _, child in runtime:GetChildren() do
				warn("    Child:", child.Name, child.ClassName)
			end
		end
	else
		warn("  runtime not found in Parent")
	end
end

print("[ClientInit] Bootstrap initiated - see runtime output above")
