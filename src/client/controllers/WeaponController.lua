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

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

local WeaponController = {}

-- ─── References ──────────────────────────────────────────────────────────────

local Player = Players.LocalPlayer

-- ─── State ───────────────────────────────────────────────────────────────────

-- Set only while the Tool is actively held in the Character (hotbar selected).
local _heldWeaponId: string? = nil

-- Set as long as the server has given us ANY weapon (backpack or held).
local _ownedWeaponId: string? = nil

-- ─── Constants ───────────────────────────────────────────────────────────────

local EQUIPPED_EVENT   = "WeaponEquipped"
local UNEQUIPPED_EVENT = "WeaponUnequipped"

-- ─── Private helpers ─────────────────────────────────────────────────────────

--[[
	Connect Equipped/Unequipped events to a Tool so we know when it moves
	between Backpack <-> Character.
]]
local function _WireToolEvents(tool: Tool)
	tool.Equipped:Connect(function()
		local id = tool:GetAttribute("WeaponId")
		if id then
			_heldWeaponId = id
			print(`[WeaponController] ✓ Tool held: {id}`)
		end
	end)

	tool.Unequipped:Connect(function()
		local id = tool:GetAttribute("WeaponId")
		print(`[WeaponController] Tool unholstered: {tostring(id)}`)
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
