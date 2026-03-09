--!strict
--[[
	AnimationLoader.lua

	Issue #55: Combat feedback and animations from project animation folder
	Epic: Phase 2 - Combat & Fluidity

	Loads character animations from the project hierarchy:
	ReplicatedStorage.animations/[Animation_Name] or
	ReplicatedStorage.animations/[Animation_Name]/Humanoid/AnimSaves/[Asset]

	Priority: DB rbxassetid lookup first, then folder-structure lookup.
	Only published Animation instances are accepted — KeyframeSequence is
	rejected with a warning (must be published to Roblox before use).
	Returns a clone suitable for Animator:LoadAnimation().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationLoader = {}

-- database of known animation asset IDs (flat name -> id)
local AnimationDatabase = require(game.ReplicatedStorage.Shared.AnimationDatabase)
local _flatDb: { [string]: string } = {}

-- build flat map on first require (handles nested tables recursively)
local function flattenTable(tbl: { [any]: any })
    for key, value in pairs(tbl) do
        if typeof(value) == "table" then
            flattenTable(value)
        elseif typeof(key) == "string" and typeof(value) == "string" then
            _flatDb[key] = value
        end
    end
end

flattenTable(AnimationDatabase)


local ANIMATIONS_FOLDER_NAME = "animations"
local HUMANOID_FOLDER_NAME = "Humanoid"
local ANIM_SAVES_NAME = "AnimSaves"

-- Cache: folder path so we don't repeatedly FindFirstChild
local _animationsFolder: Folder? = nil

--[[
	@return Folder or nil if not found
]]
local function getAnimationsFolder(): Folder?
	if _animationsFolder then
		return _animationsFolder
	end
	local folder = ReplicatedStorage:FindFirstChild(ANIMATIONS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		_animationsFolder = folder :: Folder
		return _animationsFolder
	end
	return nil
end

--[[
	Get an animation or keyframe sequence instance from the project.
	Supports multiple structures:
	  1. animations/[FolderName]/Humanoid/AnimSaves/[AssetName] (recommended)
	  2. animations/[FolderName]/AnimSaves/[AssetName] (Studio standard)
	  3. animations/[FolderName]/[AssetName] (direct)

	@param folderName Display name of the animation folder (e.g. "Back Roll", "Front Roll")
	@param assetName Optional. Specific asset name under AnimSaves (e.g. "BackRoll"). If nil, uses first Animation or KeyframeSequence found.
	@return Instance? A clone of the Animation or KeyframeSequence, or nil if not found. Caller must LoadAnimation and Destroy when done.
]]
function AnimationLoader.GetAnimation(folderName: string, assetName: string?): (Instance)?
	-- DB lookup for single-animation keys (movement states, ability casts).
	-- Skip when assetName is provided: weapon combos and multi-asset folders must
	-- go through the folder structure so the specific asset is retrieved correctly.
	if (not assetName or assetName == "") and _flatDb[folderName] then
		local assetId = _flatDb[folderName]
		if assetId ~= "" and assetId ~= "rbxassetid://0" and assetId ~= "rbxassetid://" then
			local anim = Instance.new("Animation")
			anim.AnimationId = assetId
			print(`[AnimationLoader] ✓ DB hit "{folderName}" -> {assetId}`)
			return anim
		end
		-- stub (0 / empty) — fall through to folder lookup or warn below
	end

	local animationsRoot = getAnimationsFolder()
	if not animationsRoot then
		warn(`[AnimationLoader] ✗ Animations folder not found at ReplicatedStorage.animations`)
		return nil
	end

	local animFolder = animationsRoot:FindFirstChild(folderName)
	if not animFolder then
		warn(`[AnimationLoader] ✗ Animation folder "{folderName}" not found in {animationsRoot:GetFullName()}`)
		return nil
	end

	-- Try multiple structure patterns:
	-- 1. FolderName/Humanoid/AnimSaves/Asset (recommended structure)
	-- 2. FolderName/AnimSaves/Asset (Studio structure without Humanoid)
	-- 3. FolderName/Asset (direct structure)
	local searchContainer = nil
	local humanoidFolder = animFolder:FindFirstChild(HUMANOID_FOLDER_NAME)
	
	if humanoidFolder then
		local animSaves = humanoidFolder:FindFirstChild(ANIM_SAVES_NAME)
		if animSaves then
			searchContainer = animSaves
			print(`[AnimationLoader] Using Humanoid/AnimSaves structure in {animFolder:GetFullName()}`)
		end
	end
	
	if not searchContainer then
		-- Try AnimSaves directly under the animation folder
		local animSaves = animFolder:FindFirstChild(ANIM_SAVES_NAME)
		if animSaves then
			searchContainer = animSaves
			print(`[AnimationLoader] Using AnimSaves structure in {animFolder:GetFullName()}`)
		else
			-- Fall back to searching directly in the animation folder
			searchContainer = animFolder
			print(`[AnimationLoader] No Humanoid/AnimSaves structure found, searching directly in {animFolder:GetFullName()}`)
		end
	end

	local template: Instance? = nil
	if assetName and assetName ~= "" then
		template = searchContainer:FindFirstChild(assetName)
		if not template then
			local childNames = {}
			for _, child in searchContainer:GetChildren() do
				table.insert(childNames, `{child.Name} ({child.ClassName})`)
			end
			warn(`[AnimationLoader] ✗ Asset "{assetName}" not found in {searchContainer:GetFullName()}`)
			warn(`[AnimationLoader]   Available children: {table.concat(childNames, ", ")}`)
		end
	else
		-- Only accept published Animation instances — KeyframeSequence is Studio-only
		-- and cannot be loaded in a live game. All animations must be published to Roblox.
		for _, child in searchContainer:GetChildren() do
			if child:IsA("Animation") then
				template = child
				break
			end
		end
		if not template then
			local childNames = {}
			for _, child in searchContainer:GetChildren() do
				table.insert(childNames, `{child.Name} ({child.ClassName})`)
			end
			warn(`[AnimationLoader] ✗ No Animation or KeyframeSequence found in {searchContainer:GetFullName()}`)
			warn(`[AnimationLoader]   Available children ({#searchContainer:GetChildren()}): {table.concat(childNames, ", ")}`)
		end
	end

	if not template then
		-- last ditch: if folderName matches db now (maybe case mismatch?)
		if folderName and _flatDb[folderName] then
			local anim = Instance.new("Animation")
			anim.AnimationId = _flatDb[folderName]
			print(`[AnimationLoader] ✓ Falling back to database animation for "{folderName}" -> {_flatDb[folderName]}`)
			return anim
		end
		return nil
	end

	-- Clone so we don't modify the template; clone is safe to pass to LoadAnimation
	local clone = template:Clone()
	print(`[AnimationLoader] ✓ Got animation: {template.Name} from {folderName}`)
	return clone
end

--[[
	Load an animation from the project and return an AnimationTrack for the given Humanoid.
	Caller is responsible for playing/stopping the track and cleaning up.

	@param humanoid The character's Humanoid (must have an Animator)
	@param folderName Animation folder name (e.g. "Front Roll")
	@param assetName Optional asset name under AnimSaves
	@return AnimationTrack?, or nil if load failed
]]
function AnimationLoader.LoadTrack(humanoid: Humanoid, folderName: string, assetName: string?): (AnimationTrack)?
	print(`[AnimationLoader] LoadTrack called: folder="{folderName}", asset="{assetName or "nil"}"`)
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn(`[AnimationLoader] ✗ No Animator found in Humanoid`)
		return nil
	end

	local instance = AnimationLoader.GetAnimation(folderName, assetName)
	if not instance then
		warn(`[AnimationLoader] ✗ GetAnimation returned nil for "{folderName}"`)
		return nil
	end

	-- Create an Animation object to load
	local animToLoad: Animation
	
	if instance:IsA("KeyframeSequence") then
		-- KeyframeSequence cannot be played in a live game — animations must be
		-- published to Roblox as Animation objects with a real rbxassetid.
		warn(`[AnimationLoader] ✗ KeyframeSequence "{instance.Name}" found for "{folderName}" — publish it as an Animation and add the asset ID to AnimationDatabase.lua.`)
		instance:Destroy()
		return nil
	elseif instance:IsA("Animation") then
		-- Published Animation — use it directly.
		animToLoad = instance
	else
		warn(`[AnimationLoader] ✗ Instance is neither Animation nor KeyframeSequence: {instance.ClassName}`)
		instance:Destroy()
		return nil
	end

	-- Load the animation
	local success, track = pcall(function()
		return animator:LoadAnimation(animToLoad)
	end)

	if not success or not track then
		warn(`[AnimationLoader] ✗ Failed to load animation: {if success then "track is nil" else tostring(track)}`)
		animToLoad:Destroy()
		return nil
	end

	print(`[AnimationLoader] ✓ LoadTrack succeeded for "{folderName}"`)
	-- LoadAnimation parents the animation; we don't need to destroy it manually when track is destroyed
	return track :: AnimationTrack
end

--[[
	Load an AnimationTrack directly from a known rbxassetid string.
	Used by the module-first lookup path: weapon/ability modules provide their
	own IDs; this function loads them without going through folder lookup or DB.

	Returns nil silently for stubs ("rbxassetid://0", empty string).

	@param humanoid  The character's Humanoid (must have an Animator)
	@param assetId   Full rbxassetid string, e.g. "rbxassetid://14319068127"
	@param debugName Optional label for log messages (e.g. "Fists/punch 1")
	@return AnimationTrack?, or nil if stub / load failed
]]
function AnimationLoader.LoadTrackFromId(humanoid: Humanoid, assetId: string, debugName: string?): AnimationTrack?
	if not assetId or assetId == "" or assetId == "rbxassetid://0" or assetId == "rbxassetid://" then
		return nil -- stub — caller falls through to DB fallback
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn("[AnimationLoader] LoadTrackFromId: No Animator found on Humanoid")
		return nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)

	if ok and track then
		print(`[AnimationLoader] ✓ LoadTrackFromId "{debugName or assetId}" -> {assetId}`)
		return track :: AnimationTrack
	else
		warn(`[AnimationLoader] ✗ LoadTrackFromId failed "{debugName or assetId}": {if ok then "nil track" else tostring(track)}`)
		anim:Destroy()
		return nil
	end
end


--[[
    Preload all database animations onto a humanoid's animator.
    Useful during client startup so that the Engine caches asset data and
    subsequent LoadTrack calls are instantaneous. Skips stub/empty IDs.

    @param humanoid  Humanoid with an Animator child
]]
function AnimationLoader.PreloadAll(humanoid: Humanoid)
    task.spawn(function()
        if not humanoid then return end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then return end

        -- preload every ID from the flat database
        for key, assetId in pairs(_flatDb) do
            if assetId and assetId ~= "" and assetId ~= "rbxassetid://0" and assetId ~= "rbxassetid://" then
                local anim = Instance.new("Animation")
                anim.AnimationId = assetId
                local ok, track = pcall(function()
                    return animator:LoadAnimation(anim)
                end)
                if ok and track then
                    track:Destroy() -- only warm cache
                else
                    anim:Destroy()
                end
            end
        end

        -- also traverse the physical animations folder to cache any
        -- non-database assets (weapon combos, custom folders, etc.)
        local animRoot = getAnimationsFolder()
        if animRoot then
            for _, folder in ipairs(animRoot:GetChildren()) do
                if folder:IsA("Folder") then
                    -- calling GetAnimation triggers folder lookups and may load
                    -- its first Animation, which primes the cache.
                    pcall(AnimationLoader.GetAnimation, folder.Name)
                end
            end
        end
    end)
end

return AnimationLoader
