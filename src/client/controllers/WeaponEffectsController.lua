--!strict
--[[
	WeaponEffectsController.lua  — Client controller
	Issue #73: VFX/SFX bindings for weapon events
	Epic #66: Modular Weapon Library & Equip System

	Handles all visual and audio feedback for the local player's equipped weapon:
	  • EquipSound     — plays once when Tool enters Character (Equipped)
	  • SwingTrail     — enabled during the attack animation window, disabled otherwise
	  • HitImpact      — particle burst at hit position on HitConfirmed
	  • Cleanup        — everything detached / disabled on Unequipped

	Asset IDs come from the weapon config (WeaponRegistry).
	Missing / empty asset IDs are silently skipped — no errors thrown.

	Dependencies (injected via :Init):
	  WeaponController — to read GetOwned() and wire tool events
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkProvider  = require(ReplicatedStorage.Shared.network.NetworkProvider)
local WeaponRegistry   = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

-- Injected via Init
local WeaponController: any = nil
local ActionController: any = nil

local WeaponEffectsController = {}

-- ─── Constants ────────────────────────────────────────────────────────────────

local Player = Players.LocalPlayer
local HIT_CONFIRMED_EVENT = "HitConfirmed"

-- ─── State ────────────────────────────────────────────────────────────────────

local _currentTool: Tool? = nil
local _swingTrail: Trail? = nil
local _equipSound: Sound? = nil
local _connections: {RBXScriptConnection} = {}

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _Disconnect()
	for _, c in _connections do
		c:Disconnect()
	end
	table.clear(_connections)
end

local function _TryPlaySound(sound: Sound?)
	if not sound then return end
	if sound.SoundId == nil or sound.SoundId == "" then return end
	sound:Play()
end

--[[
	Load / find the EquipSound inside a tool. Returns nil if absent or asset empty.
]]
local function _FindOrCreateEquipSound(tool: Tool, assetId: string?): Sound?
	if not assetId or assetId == "" then return nil end
	local existing = tool:FindFirstChildOfClass("Sound")
	if existing then
		return existing
	end
	local s = Instance.new("Sound")
	s.Name = "EquipSound"
	s.SoundId = assetId
	s.Volume = 1
	s.RollOffMaxDistance = 40
	s.Parent = tool
	return s
end

--[[
	Find the SwingTrail inside a tool handle (or the tool root itself).
]]
local function _FindSwingTrail(tool: Tool): Trail?
	-- Check tool handle first, then tool root
	local handle = tool:FindFirstChild("Handle")
	local root = handle or tool
	return root:FindFirstChildOfClass("Trail")
end

--[[
	Spawn a temporary hit-impact particle at worldPos using the given asset ID.
]]
local function _SpawnHitImpact(worldPos: Vector3, assetId: string?)
	if not assetId or assetId == "" then return end

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = worldPos

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = assetId
	emitter.Lifetime = NumberRange.new(0.15, 0.3)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 15)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.LightEmission = 0.5
	emitter.Parent = attachment

	-- Parent to workspace so it shows globally
	attachment.Parent = workspace

	-- Emit a burst then clean up
	emitter:Emit(12)
	task.delay(0.6, function()
		attachment:Destroy()
	end)
end

-- ─── Tool lifecycle ───────────────────────────────────────────────────────────

--[[
	Wire up all per-tool effects when the player equips (holds) a tool.
]]
local function _OnToolEquipped(tool: Tool, weaponConfig: any)
	_currentTool = tool

	-- EquipSound
	local equipSoundAsset = weaponConfig.Effects and weaponConfig.Effects.EquipSound
	_equipSound = _FindOrCreateEquipSound(tool, equipSoundAsset)
	_TryPlaySound(_equipSound)

	-- SwingTrail — disabled by default; enabled via external signal during attack window
	_swingTrail = _FindSwingTrail(tool)
	if _swingTrail then
		_swingTrail.Enabled = false
	end

	print(("[WeaponEffectsController] ✓ Effects armed for %s"):format(weaponConfig.Id))
end

--[[
	Clean up all effects when the tool is put away / unequipped.
]]
local function _OnToolUnequipped()
	if _swingTrail then
		_swingTrail.Enabled = false
		_swingTrail = nil
	end
	_equipSound = nil
	_currentTool = nil
	print("[WeaponEffectsController] Effects cleaned up")
end

-- ─── Attack window hooks ──────────────────────────────────────────────────────

--[[
	Call this from ActionController (or listen to its events) at attack-animation start.
	Enables the swing trail for `duration` seconds.
]]
function WeaponEffectsController.OnAttackStart(duration: number?)
	if not _swingTrail then return end
	_swingTrail.Enabled = true
	local trail = _swingTrail
	task.delay(duration or 0.4, function()
		if trail then
			trail.Enabled = false
		end
	end)
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function WeaponEffectsController:Init(dependencies: {[string]: any}?)
	print("[WeaponEffectsController] Initializing...")

	if dependencies then
		WeaponController = dependencies.WeaponController
		ActionController = dependencies.ActionController
	end

	print("[WeaponEffectsController] Initialized")
end

function WeaponEffectsController:Start()
	print("[WeaponEffectsController] Starting...")

	-- Watch the character's backpack for the weapon Tool
	local function _WatchCharacter(character: Model)
		_Disconnect()

		-- Listen: Tool enters Character (held = Equipped)
		local c1 = character.ChildAdded:Connect(function(child)
			if not child:IsA("Tool") then return end
			local tool = child :: Tool
			local wid = tool:GetAttribute("WeaponId")
			if not wid then return end
			local config = WeaponRegistry.Get(wid :: string)
			if not config then return end

			_OnToolEquipped(tool, config)

			-- Tool removed from Character (unequipped to backpack or dropped)
			local c2 = tool.AncestryChanged:Connect(function(_, newParent)
				if newParent ~= character then
					_OnToolUnequipped()
				end
			end)
			table.insert(_connections, c2)
		end)
		table.insert(_connections, c1)

		-- Handle tools already held at module load
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				local tool = child :: Tool
				local wid = tool:GetAttribute("WeaponId")
				if wid then
					local config = WeaponRegistry.Get(wid :: string)
					if config then
						_OnToolEquipped(tool, config)
					end
				end
			end
		end
	end

	-- Wire character (current + future respawns)
	if Player.Character then
		_WatchCharacter(Player.Character)
	end
	Player.CharacterAdded:Connect(_WatchCharacter)

	-- ─── HitConfirmed → HitImpact ─────────────────────────────────────────────
	local hitEvent = NetworkProvider:GetRemoteEvent(HIT_CONFIRMED_EVENT)
	if hitEvent then
		hitEvent.OnClientEvent:Connect(function(
			attacker: Player | any,
			_target: any,
			_damage: number,
			_isCritical: boolean?,
			_isDummy: boolean?
		)
			-- Only play impact for hits we land (local attacker)
			if attacker ~= Player then return end

			local weaponId = WeaponController and WeaponController.GetOwned()
			if not weaponId then return end
			local config = WeaponRegistry.Get(weaponId)
			if not config then return end

			local impactAsset = config.Effects and config.Effects.HitImpact
			if not impactAsset or impactAsset == "" then return end

			-- Use character HRP position as approximate hit world position
			local char = Player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local worldPos = hrp and hrp.Position or Vector3.new(0, 0, 0)
			_SpawnHitImpact(worldPos, impactAsset)
		end)
	end

	print("[WeaponEffectsController] Started")
end

return WeaponEffectsController
