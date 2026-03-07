--!strict
--[[
	WeaponController.lua

	Issue #69: Weapon Equip System
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Client-side controller that tracks which weapon tool the local player is
	actively HOLDING (tool parented to Character, selected in hotbar).

	Having a weapon in the Backpack does NOT count as equipped here —
	the player must select the slot / press 1 to hold it.

	Public API:
		WeaponController.GetEquipped()  -> string?   weapon id while tool is held
		WeaponController.GetOwned()     -> string?   weapon id while tool is owned (backpack or held)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NetworkProvider  = require(ReplicatedStorage.Shared.network.NetworkProvider)
local WeaponRegistry   = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

local WeaponController = {}

-- ─── References ──────────────────────────────────────────────────────────────

local Player = Players.LocalPlayer

-- ─── State ───────────────────────────────────────────────────────────────────

-- Set only while the Tool is actively held in the Character (hotbar selected).
local _heldWeaponId: string? = nil

-- Set as long as the server has given us ANY weapon (backpack or held).
local _ownedWeaponId: string? = nil

-- Placeholder Part per Tool — keyed by Tool instance, cleared on unequip.
local _placeholderParts: {[Tool]: Part} = {}

-- ─── Constants ───────────────────────────────────────────────────────────────

local EQUIPPED_EVENT   = "WeaponEquipped"
local UNEQUIPPED_EVENT = "WeaponUnequipped"

-- Color by WeightClass (placeholder visual only — no real art)
local WEIGHT_CLASS_COLORS: {[string]: Color3} = {
	Light  = Color3.fromRGB(192, 200, 210), -- silver
	Medium = Color3.fromRGB(100, 110, 125), -- gray-blue steel
	Heavy  = Color3.fromRGB( 55,  58,  65), -- dark steel
}
local DEFAULT_PLACEHOLDER_COLOR = Color3.fromRGB(130, 130, 130)

-- ─── Private helpers ─────────────────────────────────────────────────────────

--[[
	Create a Range-scaled placeholder Part inside `tool` so the player can
	see they are holding a weapon before real art assets exist.

	The Part is welded to the Tool's Handle.  Fists skip this entirely.
	Safe to call multiple times — destroys any previous placeholder first.
]]
local function _createPlaceholderPart(tool: Tool, weaponId: string)
	-- Fists have no visible model
	if weaponId == "fists" then return end

	local config = WeaponRegistry.Get(weaponId)
	if not config then return end

	-- Find or synthesise a Handle (Tools require one to work in Roblox)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		local h = Instance.new("Part")
		h.Name       = "Handle"
		h.Size       = Vector3.new(0.2, 0.2, 0.2)
		h.Transparency = 1
		h.CanCollide = false
		h.Parent     = tool
		handle       = h
	end

	-- Destroy any leftover placeholder from a previous equip
	local existing = _placeholderParts[tool]
	if existing then
		existing:Destroy()
		_placeholderParts[tool] = nil :: any
	end

	-- Build the blade / body Part
	local blade       = Instance.new("Part")
	blade.Name        = "PlaceholderBlade"
	blade.Size        = Vector3.new(0.2, 0.2, config.Range or 3)
	blade.CFrame      = (handle :: BasePart).CFrame * CFrame.new(0, 0, -(config.Range or 3) / 2)
	blade.Color       = WEIGHT_CLASS_COLORS[config.WeightClass] or DEFAULT_PLACEHOLDER_COLOR
	blade.Material    = Enum.Material.SmoothPlastic
	blade.CanCollide  = false
	blade.CastShadow  = false
	blade.Anchored    = false
	blade.Parent      = tool

	-- Weld blade to Handle so it follows character arm movement
	local weld          = Instance.new("WeldConstraint")
	weld.Part0          = handle :: BasePart
	weld.Part1          = blade
	weld.Parent         = blade

	_placeholderParts[tool] = blade
end

--[[
	Remove the placeholder Part from `tool` and clear the reference table.
]]
local function _removePlaceholderPart(tool: Tool)
	local part = _placeholderParts[tool]
	if part then
		part:Destroy()
		_placeholderParts[tool] = nil :: any
	end
end

--[[
	Connect Equipped/Unequipped events to a Tool so we know when it moves
	between Backpack <-> Character.
]]
local function _WireToolEvents(tool: Tool)
	tool.Equipped:Connect(function()
		local id = tool:GetAttribute("WeaponId")
		if id then
			_heldWeaponId = id
			_createPlaceholderPart(tool, id)
			print(`[WeaponController] ✓ Tool held: {id}`)
		end
	end)

	tool.Unequipped:Connect(function()
		local id = tool:GetAttribute("WeaponId")
		print(`[WeaponController] Tool unholstered: {tostring(id)}`)
		_removePlaceholderPart(tool)
		_heldWeaponId = nil
	end)
end

--[[
    PATCH for WeaponController.lua

    Replace the _ScanAndWire function entirely with this version.

    Change from previous patch:
    - Removed the auto-select block that moved a tool from Backpack → Character.
    - The player now spawns with weapons in Backpack (owned by WeaponService)
      but NONE held/equipped. They must press 1 or click the weapon's hotbar slot
      to physically hold the tool.
    - _WireToolEvents is still called for all backpack tools so held/unhold events
      fire correctly when the player does choose to hold a weapon.
]]

local function _ScanAndWire()
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, item in backpack:GetChildren() do
            if item:IsA("Tool") and item:GetAttribute("WeaponId") then
                _WireToolEvents(item :: Tool)
            end
        end
        -- Wire future additions (e.g. weapon swaps from WeaponService)
        backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and child:GetAttribute("WeaponId") then
                _WireToolEvents(child :: Tool)
            end
        end)
    end

    -- If a tool is already physically held when we scan (e.g. respawn edge case),
    -- record it so _heldWeaponId is accurate.
    local character = Player.Character
    if character then
        local held = character:FindFirstChildOfClass("Tool")
        if held and held:GetAttribute("WeaponId") then
            _heldWeaponId = held:GetAttribute("WeaponId") :: string
            print(`[WeaponController] ✓ Tool already held on scan: {_heldWeaponId}`)
        end
        -- No auto-equip here — player spawns unarmed, weapons stay in Backpack.
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Returns the weapon id only while the player is actively HOLDING it.
	Nil when in backpack but not selected.
	@return string?
]]
function WeaponController.GetEquipped(): string?
	return _heldWeaponId
end

--[[
	Returns the weapon id the server has assigned (owned), regardless of
	whether the tool is held or sitting in the backpack.
	@return string?
]]
function WeaponController.GetOwned(): string?
	return _ownedWeaponId
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function WeaponController:Init(dependencies: {[string]: any}?)
	print("[WeaponController] Initializing...")
	print("[WeaponController] Initialized successfully")
end

function WeaponController:Start()
	print("[WeaponController] Starting...")

	-- Restore server-assigned ownership from the character attribute
	-- (set before this controller starts; avoids broadcast race).
	local character = Player.Character
	if character then
		local existing = character:GetAttribute("EquippedWeapon")
		if existing and existing ~= "" then
			_ownedWeaponId = existing
			print(`[WeaponController] ✓ Owned weapon from attribute: {existing}`)
		end
	end

	-- Wire up existing tools, then watch for respawn.
	_ScanAndWire()

	Player.CharacterAdded:Connect(function()
		-- Clear all placeholder Parts — they lived in the old character's tools
		for tool, part in _placeholderParts do
			part:Destroy()
		end
		table.clear(_placeholderParts)
		_heldWeaponId  = nil
		_ownedWeaponId = nil
		task.defer(_ScanAndWire)
	end)

	-- Server broadcast: weapon granted (owned but not yet held)
	local equippedEvent = NetworkProvider:GetRemoteEvent(EQUIPPED_EVENT)
	if equippedEvent then
		equippedEvent.OnClientEvent:Connect(function(who: Player, weaponId: string)
			if who == Player then
				_ownedWeaponId = weaponId
				print(`[WeaponController] ✓ Weapon owned: {weaponId}`)
				-- attempt to equip the tool locally if it exists in backpack
				task.defer(function()
					local backpack = Player:FindFirstChildOfClass("Backpack")
					if backpack then
						for _, tool in ipairs(backpack:GetChildren()) do
							if tool:IsA("Tool") and tool:GetAttribute("WeaponId") == weaponId then
								local humanoid = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
								if humanoid then
									humanoid:EquipTool(tool)
								end
								break
							end
						end
					end
				end)
			end
		end)
	end

	-- Server broadcast: weapon taken away entirely
	local unequippedEvent = NetworkProvider:GetRemoteEvent(UNEQUIPPED_EVENT)
	if unequippedEvent then
		unequippedEvent.OnClientEvent:Connect(function(who: Player)
			if who == Player then
				_heldWeaponId  = nil
				_ownedWeaponId = nil
				print("[WeaponController] Weapon ownership removed")
			end
		end)
	end

	print("[WeaponController] Started successfully")
end

return WeaponController
