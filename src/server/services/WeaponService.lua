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

	CHANGES from original:
	- _EquipDefault: gives fists Tool to Backpack only, does NOT call EquipWeapon.
	  Player spawns unarmed. They must drag fists to the hotbar and click to hold.
	- EquipWeapon: removed "already equipped" guard. Now does a proper swap —
	  sheathe current weapon first (Character → Backpack), then hold new one.
	- UnequipWeapon: no longer calls _RemoveTool (which destroyed the tool forever).
	  Now sheathes by moving Tool Character → Backpack. Tool stays, re-equippable.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkProvider  = require(ReplicatedStorage.Shared.network.NetworkProvider)
local WeaponRegistry   = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local StateService     = require(ReplicatedStorage.Shared.modules.StateService)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)

local WeaponService = {}

-- ─── Storage ─────────────────────────────────────────────────────────────────

-- Keyed by player UserId; value is the weapon Id currently HELD (in Character).
-- nil means unarmed (tool may still be in Backpack).
local EquippedWeapons: {[number]: string} = {}

-- ─── Anti-cheat (#74) ────────────────────────────────────────────────────────

local _lastAttackTime: {[number]: number} = {}
local _strikes: {[number]: number} = {}

local SERVER_ATTACK_COOLDOWN    = 0.05
local SERVER_RANGE_TOLERANCE    = 3
local MAX_DAMAGE_MULTIPLIER     = 2.0
local MAX_VIOLATIONS_BEFORE_KICK = 3

-- ─── Constants ───────────────────────────────────────────────────────────────

local EQUIP_EVENT_NAME     = "EquipWeapon"
local UNEQUIP_EVENT_NAME   = "UnequipWeapon"
local EQUIPPED_BROADCAST   = "WeaponEquipped"
local UNEQUIPPED_BROADCAST = "WeaponUnequipped"

local ATTR_EQUIPPED = "EquippedWeapon"

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function _GiveTool(player: Player, config: any)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		warn(`[WeaponService] No Backpack found for {player.Name} — cannot give tool`)
		return
	end

	-- Remove any leftover tool with the same weapon id first (safety).
	for _, item in backpack:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("WeaponId") == config.Id then
			item:Destroy()
		end
	end

	local tool = Instance.new("Tool")
	tool.Name           = config.Name
	tool.ToolTip        = config.Description or ""
	tool.RequiresHandle = false
	tool.CanBeDropped   = false
	tool:SetAttribute("WeaponId", config.Id)

	if config.GripOffset then
		tool.GripPos     = config.GripOffset.Position
		tool.GripRight   = config.GripOffset.RightVector
		tool.GripUp      = config.GripOffset.UpVector
		tool.GripForward = config.GripOffset.LookVector
	end

	tool.Parent = backpack
	print(`[WeaponService] ✓ Tool '{tool.Name}' added to {player.Name}'s Backpack`)
end

-- Sheathe: move Tool from Character back to Backpack. Does NOT destroy it.
local function _SheatheTool(player: Player, weaponId: string)
	local char = player.Character
	local bp   = player:FindFirstChildOfClass("Backpack")
	if char and bp then
		for _, item in char:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
				item.Parent = bp
				return
			end
		end
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function WeaponService.RecordViolation(player: Player, reason: string)
	local uid = player.UserId
	_strikes[uid] = (_strikes[uid] or 0) + 1
	warn(("[WeaponService] ⚠  Strike %d/%d for %s — %s"):format(
		_strikes[uid], MAX_VIOLATIONS_BEFORE_KICK, player.Name, reason))
	if _strikes[uid] >= MAX_VIOLATIONS_BEFORE_KICK then
		player:Kick("Anti-cheat: excessive violation count.")
	end
end

function WeaponService.ValidateAttack(player: Player, hitData: any): (boolean, number)
	local uid     = player.UserId
	local now     = tick()
	local last    = _lastAttackTime[uid] or 0
	if now - last < SERVER_ATTACK_COOLDOWN then
		WeaponService.RecordViolation(player, "attack too fast")
		return false, 0
	end
	_lastAttackTime[uid] = now

	local weaponId = EquippedWeapons[uid]
	if not weaponId then return false, 0 end
	local config = WeaponRegistry.Get(weaponId)
	if not config then return false, 0 end

	local damage = hitData and hitData.Damage or 0
	local cap    = config.BaseDamage * MAX_DAMAGE_MULTIPLIER
	if damage > cap then
		WeaponService.RecordViolation(player, "damage over cap")
		damage = cap
	end

	return true, damage
end

function WeaponService.GetEquipped(player: Player): string?
	return EquippedWeapons[player.UserId]
end

--[[
	Equip (hold/draw) a weapon for a player.
	If the player is already holding a different weapon, sheathe it first.
	The tool must already be in the player's Backpack (given by _EquipDefault
	or a previous equip). If it's missing, _GiveTool is called to create it.
]]
function WeaponService.EquipWeapon(player: Player, weaponId: string)
	local humanoid = _GetHumanoid(player)
	if not humanoid then
		warn(`[WeaponService] Equip denied for {player.Name} — no character/humanoid`)
		return
	end
	if humanoid.Health <= 0 then
		warn(`[WeaponService] Equip denied for {player.Name} — player is dead`)
		return
	end

	if not WeaponRegistry.Has(weaponId) then
		warn(`[WeaponService] Unknown weapon id "{weaponId}" requested by {player.Name}`)
		return
	end

	local current = EquippedWeapons[player.UserId]

	-- Already holding the same weapon — no-op
	if current == weaponId then return end

	-- Sheathe current weapon first (move Character → Backpack, don't destroy)
	if current then
		_SheatheTool(player, current)
		EquippedWeapons[player.UserId] = nil
		if player.Character then
			player.Character:SetAttribute(ATTR_EQUIPPED, nil)
		end
	end

	-- Discipline cross-training warning (kept from original, non-blocking)
	local config = WeaponRegistry.Get(weaponId)
	if config and config.WeightClass then
		local ok, playerData = pcall(function()
			return StateService and StateService.GetPlayerData
				and StateService:GetPlayerData(player) or nil
		end)
		if ok and playerData then
			local ok2, discCfg = pcall(function()
				return DisciplineConfig and DisciplineConfig.Get
					and DisciplineConfig.Get(playerData.DisciplineId) or nil
			end)
			if ok2 and discCfg and discCfg.weaponClasses then
				if not table.find(discCfg.weaponClasses, config.WeightClass) then
					warn(`[WeaponService] {player.Name} cross-training: {config.WeightClass}`)
				end
			end
		end
	end

	-- Store as held
	EquippedWeapons[player.UserId] = weaponId
	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, weaponId)
	end

	-- Move Tool Backpack → Character to physically hold it.
	-- If the tool doesn't exist yet in the backpack, create it first.
	local bp   = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	local toolFound = false

	if bp then
		for _, item in bp:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
				if char then item.Parent = char end
				toolFound = true
				break
			end
		end
	end

	if not toolFound then
		if config then _GiveTool(player, config) end
		-- _GiveTool parents to Backpack; now move to Character
		local bp2 = player:FindFirstChildOfClass("Backpack")
		if bp2 and char then
			for _, item in bp2:GetChildren() do
				if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
					item.Parent = char
					break
				end
			end
		end
	end

	print(`[WeaponService] ✓ {player.Name} equipped "{weaponId}"`)

	local equippedEvent = NetworkProvider:GetRemoteEvent(EQUIPPED_BROADCAST)
	if equippedEvent then
		equippedEvent:FireAllClients(player, weaponId)
	end
end

--[[
	Unequip (sheathe) the current weapon for a player.
	Moves the Tool Character → Backpack. Does NOT destroy it.
]]
function WeaponService.UnequipWeapon(player: Player)
	local current = EquippedWeapons[player.UserId]
	if not current then return end

	EquippedWeapons[player.UserId] = nil

	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, nil)
	end

	-- Sheathe: move Tool back to Backpack, keep it alive
	_SheatheTool(player, current)

	print(`[WeaponService] ✓ {player.Name} sheathed "{current}"`)

	local unequippedEvent = NetworkProvider:GetRemoteEvent(UNEQUIPPED_BROADCAST)
	if unequippedEvent then
		unequippedEvent:FireAllClients(player)
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

--[[
	Give the player their fists tool on spawn.
	Does NOT call EquipWeapon — player spawns UNARMED.
	EquippedWeapons stays nil so the first EquipWeapon call from the hotbar works.
]]
local function _EquipDefault(player: Player)
	-- Clear any stale held state from a previous life
	EquippedWeapons[player.UserId] = nil
	if player.Character then
		player.Character:SetAttribute(ATTR_EQUIPPED, nil)
	end

	-- Wait for Humanoid (CharacterAdded fires before children are ready)
	if player.Character then
		player.Character:WaitForChild("Humanoid", 10)
	end

	-- Give fists Tool to Backpack so it's available to equip from the hotbar
	local config = WeaponRegistry.Get("fists")
	if config then
		_GiveTool(player, config)
	end
end

function WeaponService:Init()
	print("[WeaponService] Initializing...")

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(_character)
			task.spawn(_EquipDefault, player)
		end)
		if player.Character then
			task.spawn(_EquipDefault, player)
		end
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(_character)
			task.spawn(_EquipDefault, player)
		end)
		if player.Character then
			task.spawn(_EquipDefault, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		EquippedWeapons[player.UserId]    = nil
		_lastAttackTime[player.UserId]    = nil
		_strikes[player.UserId]           = nil
	end)

	print("[WeaponService] Initialized successfully")
end

function WeaponService:Start()
	print("[WeaponService] Starting...")

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

	local unequipEvent = NetworkProvider:GetRemoteEvent(UNEQUIP_EVENT_NAME)
	if unequipEvent then
		unequipEvent.OnServerEvent:Connect(function(player)
			WeaponService.UnequipWeapon(player)
		end)
	end

	print("[WeaponService] Started successfully")
end

return WeaponService