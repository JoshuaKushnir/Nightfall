--!strict
--[[
	AnimationLoader.lua

	Issue #55: Combat feedback and animations from project animation folder
	Epic: Phase 2 - Combat & Fluidity

	Loads character animations from the project hierarchy:
	ReplicatedStorage.animations/[Animation_Name] or
	ReplicatedStorage.animations/[Animation_Name]/Humanoid/AnimSaves/[Asset]

	Supports both Animation (AnimationId) and KeyframeSequence instances.
	Returns a clone suitable for Animator:LoadAnimation().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local AnimationLoader = {}

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
		-- Prefer Animation (has a published AssetId) over KeyframeSequence (Studio-only registration)
		for _, child in searchContainer:GetChildren() do
			if child:IsA("Animation") then
				template = child
				break
			end
		end
		-- Fall back to KeyframeSequence only if no Animation found
		if not template then
			for _, child in searchContainer:GetChildren() do
				if child:IsA("KeyframeSequence") then
					template = child
					break
				end
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
		-- RegisterKeyframeSequence only works in Studio; in a live game animations
		-- must be published to Roblox with a real asset ID (Animation objects).
		if not RunService:IsStudio() then
			warn(`[AnimationLoader] ✗ KeyframeSequence "{instance.Name}" cannot be used in a live game. Publish the animation to Roblox and replace it with an Animation object containing the asset ID.`)
			instance:Destroy()
			return nil
		end
		-- In Studio: register to get a temporary asset ID
		print(`[AnimationLoader] Registering KeyframeSequence: {instance.Name}`)
		local success, temporaryAssetId = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(instance)
		end)
		
		if not success or not temporaryAssetId then
			warn(`[AnimationLoader] ✗ Failed to register KeyframeSequence: {if success then "no asset ID" else tostring(temporaryAssetId)}`)
			instance:Destroy()
			return nil
		end
		
		print(`[AnimationLoader] ✓ Registered KeyframeSequence with asset ID: {temporaryAssetId}`)
		
		-- Create Animation object with the temporary asset ID
		animToLoad = Instance.new("Animation")
		animToLoad.AnimationId = temporaryAssetId
		
		-- Clean up the original instance
		instance:Destroy()
	elseif instance:IsA("Animation") then
		-- Already an Animation, use it directly
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

return AnimationLoader
