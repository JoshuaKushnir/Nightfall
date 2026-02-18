--!strict
--[[
	WeaponService.lua

	Issue #69: Weapon Equip System
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Server-side handler for weapon equip/unequip.
	Validates player state, looks up weapons via WeaponRegistry, stores the
	equipped weapon id per-player, and broadcasts changes to all clients.

	Public API:
		WeaponService.GetEquipped(player) -> string?
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)

local WeaponService = {}

-- ─── Storage ─────────────────────────────────────────────────────────────────

-- Keyed by player UserId; value is the equipped weapon Id
local EquippedWeapons: {[number]: string} = {}

-- ─── Constants ───────────────────────────────────────────────────────────────

local EQUIP_EVENT_NAME     = "EquipWeapon"
local UNEQUIP_EVENT_NAME   = "UnequipWeapon"
local EQUIPPED_BROADCAST   = "WeaponEquipped"
local UNEQUIPPED_BROADCAST = "WeaponUnequipped"

local ATTR_EQUIPPED = "EquippedWeapon" -- StringValue attribute set on the player Character

-- ─── Private helpers ─────────────────────────────────────────────────────────

--[[
	Return the Humanoid for a player's current character, or nil.
	@param player Player
	@return Humanoid?
]]
local function _GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Return the currently equipped weapon Id for a player, or nil.
	@param player The player to query.
	@return string?
]]
function WeaponService.GetEquipped(player: Player): string?
	return EquippedWeapons[player.UserId]
end

--[[
	Equip a weapon for a player.
	Validates humanoid health, ensures no weapon is already equipped, and
	confirms the weapon exists in WeaponRegistry before proceeding.
	@param player    The requesting player.
	@param weaponId  The Id from WeaponRegistry.
]]
function WeaponService.EquipWeapon(player: Player, weaponId: string)
	-- Validate humanoid exists and player is alive
	local humanoid = _GetHumanoid(player)
	if not humanoid then
		warn(`[WeaponService] Equip denied for {player.Name} — no character/humanoid`)
		return
	end
	if humanoid.Health <= 0 then
		warn(`[WeaponService] Equip denied for {player.Name} — player is dead`)
		return
	end

	-- Reject if already holding a weapon
	if EquippedWeapons[player.UserId] then
		warn(`[WeaponService] Equip denied for {player.Name} — "{EquippedWeapons[player.UserId]}" is already equipped`)
		return
	end

	-- Validate weapon exists in registry
	if not WeaponRegistry.Has(weaponId) then
		warn(`[WeaponService] Unknown weapon id "{weaponId}" requested by {player.Name}`)
		return
	end

	-- Store
	EquippedWeapons[player.UserId] = weaponId

	-- Set attribute on the Character
	local character = player.Character
	if character then
		character:SetAttribute(ATTR_EQUIPPED, weaponId)
	end

	print(`[WeaponService] ✓ {player.Name} equipped "{weaponId}"`)

	-- Broadcast to all clients
	local equippedEvent = NetworkProvider:GetRemoteEvent(EQUIPPED_BROADCAST)
	if equippedEvent then
		equippedEvent:FireAllClients(player, weaponId)
	end
end

--[[
	Unequip the current weapon for a player.
	Clears the Character attribute and broadcasts to all clients.
	@param player The requesting player.
]]
function WeaponService.UnequipWeapon(player: Player)
	local current = EquippedWeapons[player.UserId]
	if not current then
		return -- Nothing to unequip
	end

	-- Clear storage
	EquippedWeapons[player.UserId] = nil

	-- Clear attribute on the Character
	local character = player.Character
	if character then
		character:SetAttribute(ATTR_EQUIPPED, nil)
	end

	print(`[WeaponService] ✓ {player.Name} unequipped "{current}"`)

	-- Broadcast to all clients
	local unequippedEvent = NetworkProvider:GetRemoteEvent(UNEQUIPPED_BROADCAST)
	if unequippedEvent then
		unequippedEvent:FireAllClients(player)
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

--[[
	Equip the default weapon (fists) for a player.
	Force-clears any existing entry so this is safe to call on respawn.
	@param player Player
]]
local function _EquipDefault(player: Player)
	-- Force-clear any stale entry so EquipWeapon doesn't reject the request.
	EquippedWeapons[player.UserId] = nil
	-- Clear the attribute too so the character starts clean.
	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, nil)
	end
	WeaponService.EquipWeapon(player, "fists")
end

--[[
	Initialize the service
]]
function WeaponService:Init()
	print("[WeaponService] Initializing...")

	-- Auto-equip fists whenever a character spawns.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(_EquipDefault, player)
		end)
		-- Handle players already in-game when the service starts.
		if player.Character then
			task.defer(_EquipDefault, player)
		end
	end)

	-- Handle players already connected before this service loaded.
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			task.defer(_EquipDefault, player)
		end)
		if player.Character then
			task.defer(_EquipDefault, player)
		end
	end

	-- Clean up when a player leaves.
	Players.PlayerRemoving:Connect(function(player)
		EquippedWeapons[player.UserId] = nil
	end)

	print("[WeaponService] Initialized successfully")
end

--[[
	Start the service — wire up remote event listeners
]]
function WeaponService:Start()
	print("[WeaponService] Starting...")

	-- Listen for equip requests from clients
	local equipEvent = NetworkProvider:GetRemoteEvent(EQUIP_EVENT_NAME)
	if equipEvent then
		equipEvent.OnServerEvent:Connect(function(player, weaponId)
			if typeof(weaponId) ~= "string" then
				warn(`[WeaponService] EquipWeapon from {player.Name} — invalid weaponId type`)
				return
			end
			WeaponService.EquipWeapon(player, weaponId)
		end)
	end

	-- Listen for unequip requests from clients
	local unequipEvent = NetworkProvider:GetRemoteEvent(UNEQUIP_EVENT_NAME)
	if unequipEvent then
		unequipEvent.OnServerEvent:Connect(function(player)
			WeaponService.UnequipWeapon(player)
		end)
	end

	print("[WeaponService] Started successfully")
end

return WeaponService
