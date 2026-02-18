--!strict
--[[
	WeaponController.lua

	Issue #69: Weapon Equip System
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Client-side controller that listens for WeaponEquipped / WeaponUnequipped
	broadcasts from the server and maintains a local cache of the local player's
	current weapon id.

	Public API:
		WeaponController.GetEquipped() -> string?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

local WeaponController = {}

-- ─── References ──────────────────────────────────────────────────────────────

local Player = Players.LocalPlayer

-- ─── State ───────────────────────────────────────────────────────────────────

-- The weapon Id currently equipped by the local player (nil = nothing equipped)
local _currentWeaponId: string? = nil

-- ─── Constants ───────────────────────────────────────────────────────────────

local EQUIPPED_EVENT   = "WeaponEquipped"
local UNEQUIPPED_EVENT = "WeaponUnequipped"

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Return the weapon Id currently equipped by the local player, or nil.
	@return string?
]]
function WeaponController.GetEquipped(): string?
	return _currentWeaponId
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

--[[
	Initialize the controller with optional dependencies injected by the Loader.
	@param dependencies  Table of other controllers keyed by name.
]]
function WeaponController:Init(dependencies: {[string]: any}?)
	print("[WeaponController] Initializing...")
	print("[WeaponController] Initialized successfully")
end

--[[
	Start the controller — wire up network listeners.
]]
function WeaponController:Start()
	print("[WeaponController] Starting...")

	-- Listen for server broadcasts about equipped weapons
	local equippedEvent = NetworkProvider:GetRemoteEvent(EQUIPPED_EVENT)
	if equippedEvent then
		equippedEvent.OnClientEvent:Connect(function(who: Player, weaponId: string)
			if who == Player then
				_currentWeaponId = weaponId
				print(`[WeaponController] Weapon equipped: {weaponId}`)
			else
				print(`[WeaponController] {who.Name} equipped: {weaponId}`)
			end
		end)
	end

	-- Listen for server broadcasts about unequipped weapons
	local unequippedEvent = NetworkProvider:GetRemoteEvent(UNEQUIPPED_EVENT)
	if unequippedEvent then
		unequippedEvent.OnClientEvent:Connect(function(who: Player)
			if who == Player then
				local previous = _currentWeaponId
				_currentWeaponId = nil
				print(`[WeaponController] Weapon unequipped (was: {tostring(previous)})`)
			else
				print(`[WeaponController] {who.Name} unequipped their weapon`)
			end
		end)
	end

	print("[WeaponController] Started successfully")
end

return WeaponController
