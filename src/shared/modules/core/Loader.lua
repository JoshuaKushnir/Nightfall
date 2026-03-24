--!strict
--[[
	Loader - Utility for loading modules from folders
	
	Issue #5: Server & Client Bootstrap/Initialization Systems
	Epic: Phase 1 - Core Framework
	
	This utility provides functions for loading ModuleScripts from folders
	in a predictable, alphabetical order. It's used by both server and client
	bootstrap systems to initialize services and controllers.
	
	Features:
	- Alphabetical loading order (predictable and deterministic)
	- Error handling for module loading failures
	- Loading time profiling
	- Hot-reload detection
	
	Usage:
		local Loader = require(ReplicatedStorage.Shared.modules.core.Loader)
		local services = Loader.LoadModules(ServerScriptService.Server.services)
		
		for name, service in services do
			if service.Init then
				service:Init()
			end
		end
]]

local RunService = game:GetService("RunService")

local Loader = {}

--[[
	Load all ModuleScripts from a folder
	Returns a dictionary of {ModuleName: RequiredModule}
	
	@param folder - The folder containing ModuleScripts
	@param deep - Whether to recursively load from subfolders (default: false)
	@return {[string]: any} - Dictionary of loaded modules
]]
function Loader.LoadModules(folder: Instance, deep: boolean?): {[string]: any}
	assert(folder, "Folder cannot be nil")
	
	local startTime = os.clock()
	local modules: {[string]: any} = {}
	local loadOrder: {string} = {}
	
	-- Collect all ModuleScripts
	local function collectModules(parent: Instance)
		for _, child in parent:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(loadOrder, child.Name)
			elseif deep and child:IsA("Folder") then
				collectModules(child)
			end
		end
	end
	
	collectModules(folder)
	
	-- Sort alphabetically for predictable load order
	table.sort(loadOrder)
	
	print(`[Loader] Loading {#loadOrder} modules from: {folder:GetFullName()}`)
	print(`[Loader] Load order: {table.concat(loadOrder, ", ")}`)
	
	-- Load modules in order
	for _, moduleName in loadOrder do
		local moduleScript = folder:FindFirstChild(moduleName, deep) :: ModuleScript?
		
		if not moduleScript then
			warn(`[Loader] Module not found: {moduleName}`)
			continue
		end
		
		local success, result = pcall(require, moduleScript)
		
		if not success then
			warn(`[Loader] Failed to load module {moduleName}: {result}`)
			continue
		end
		
		modules[moduleName] = result
		print(`[Loader] ✓ Loaded: {moduleName}`)
	end
	
	local loadTime = (os.clock() - startTime) * 1000
	print(`[Loader] Loaded {#loadOrder} modules in {math.floor(loadTime * 100) / 100}ms`)
	
	return modules
end

--[[
	Load a single module with error handling
	
	@param moduleScript - The ModuleScript to require
	@return any? - The required module, or nil if loading failed
]]
function Loader.LoadModule(moduleScript: ModuleScript): any?
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "Must provide a valid ModuleScript")
	
	local success, result = pcall(require, moduleScript)
	
	if not success then
		warn(`[Loader] Failed to load module {moduleScript.Name}: {result}`)
		return nil
	end
	
	return result
end

--[[
	Initialize modules by calling their Init() method
	
	@param modules - Dictionary of modules to initialize
	@param dependencies - Optional dictionary of dependencies to pass to Init()
]]
function Loader.InitializeModules(modules: {[string]: any}, dependencies: {[string]: any}?)
	print(`[Loader] Initializing {table.getn(modules)} modules...`)
	
	local startTime = os.clock()
	local initialized = 0
	
	for name, module in modules do
		if type(module) == "table" and module.Init then
			local success, err = pcall(module.Init, dependencies)
			
			if not success then
				warn(`[Loader] Failed to initialize {name}: {err}`)
			else
				initialized += 1
				print(`[Loader] ✓ Initialized: {name}`)
			end
		end
	end
	
	local initTime = (os.clock() - startTime) * 1000
	print(`[Loader] Initialized {initialized} modules in {math.floor(initTime * 100) / 100}ms`)
end

--[[
	Start modules by calling their Start() method
	
	@param modules - Dictionary of modules to start
]]
function Loader.StartModules(modules: {[string]: any})
	print(`[Loader] Starting modules...`)
	
	local startTime = os.clock()
	local started = 0
	
	for name, module in modules do
		if type(module) == "table" and module.Start then
			local success, err = pcall(module.Start)
			
			if not success then
				warn(`[Loader] Failed to start {name}: {err}`)
			else
				started += 1
				print(`[Loader] ✓ Started: {name}`)
			end
		end
	end
	
	local startTimeElapsed = (os.clock() - startTime) * 1000
	print(`[Loader] Started {started} modules in {math.floor(startTimeElapsed * 100) / 100}ms`)
end

--[[
	Check if running in Studio (for hot-reload support)
	
	@return boolean - True if running in Studio, false otherwise
]]
function Loader.IsStudio(): boolean
	return RunService:IsStudio()
end

--[[
	Check if running on server
	
	@return boolean - True if server, false if client
]]
function Loader.IsServer(): boolean
	return RunService:IsServer()
end

--[[
	Check if running on client
	
	@return boolean - True if client, false if server
]]
function Loader.IsClient(): boolean
	return RunService:IsClient()
end

--[[
	Get the current execution context (Studio/Server/Client)
	
	@return string - "Studio" | "Server" | "Client"
]]
function Loader.GetContext(): string
	if Loader.IsStudio() then
		return "Studio"
	elseif Loader.IsServer() then
		return "Server"
	else
		return "Client"
	end
end

return Loader
