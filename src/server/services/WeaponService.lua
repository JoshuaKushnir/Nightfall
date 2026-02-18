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

-- ─── Anti-cheat (#74) ────────────────────────────────────────────────────────

-- Server-side attack cooldown — last confirmed hit time per player
local _lastAttackTime: {[number]: number} = {}
-- Strike counter — accumulated violations per player (3 = kick)
local _strikes: {[number]: number} = {}

-- Minimum seconds between server-confirmed attacks (50 ms)
local SERVER_ATTACK_COOLDOWN = 0.05
-- Extra studs added to weapon.Range for server tolerance
local SERVER_RANGE_TOLERANCE = 3
-- Max damage multiplier vs weapon.BaseDamage (caps runaway damage packets)
local MAX_DAMAGE_MULTIPLIER = 2.0
-- Hits allowed above MAX_DAMAGE_MULTIPLIER before striking
local MAX_VIOLATIONS_BEFORE_KICK = 3

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

--[[
	Create a Roblox Tool for the given weapon config and parent it to the
	player's Backpack so it appears in the hotbar.
	@param player   The player who will receive the tool.
	@param config   The WeaponConfig table from WeaponRegistry.
]]
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
	tool.Name            = config.Name
	tool.ToolTip         = config.Description or ""
	tool.RequiresHandle  = false   -- no physical Handle part needed
	tool.CanBeDropped    = false   -- weapons are not droppable
	tool:SetAttribute("WeaponId", config.Id)

	-- Grip offset from config (defaults to identity if not set).
	if config.GripOffset then
		tool.GripPos   = config.GripOffset.Position
		tool.GripRight  = config.GripOffset.RightVector
		tool.GripUp     = config.GripOffset.UpVector
		tool.GripForward = config.GripOffset.LookVector
	end

	tool.Parent = backpack
	print(`[WeaponService] ✓ Tool '{tool.Name}' added to {player.Name}'s Backpack`)
end

--[[
	Remove the Tool matching weaponId from the player's Backpack and Character.
	@param player   The player whose tool should be removed.
	@param weaponId Weapon Id to find and destroy.
]]
local function _RemoveTool(player: Player, weaponId: string)
	local function clearFrom(parent: Instance?)
		if not parent then return end
		for _, item in parent:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("WeaponId") == weaponId then
				item:Destroy()
			end
		end
	end
	clearFrom(player:FindFirstChildOfClass("Backpack"))
	clearFrom(player.Character)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Anti-cheat: record a strike against a player for sending suspicious data.
	If the strike counter reaches MAX_VIOLATIONS_BEFORE_KICK the player is kicked.
]]
function WeaponService.RecordViolation(player: Player, reason: string)
	local uid = player.UserId
	_strikes[uid] = (_strikes[uid] or 0) + 1
	warn(("[WeaponService] ⚠  Strike %d/%d for %s — %s"):format(
		_strikes[uid], MAX_VIOLATIONS_BEFORE_KICK, player.Name, reason))
	if _strikes[uid] >= MAX_VIOLATIONS_BEFORE_KICK then
		player:Kick("Anti-cheat: excessive violation count.")
	end
end

--[[
	Anti-cheat: validate a client attack request before damage is applied.
	Checks per-player fire-rate and optionally validates range + damage ceiling.

	@param player       The attacker
	@param hitData      The hitData table from the network packet
	@return ok(bool), clampedDamage(number)
	         ok=false means the hit should be rejected entirely.
]]
function WeaponService.ValidateAttack(player: Player, hitData: {[string]: any}): (boolean, number)
	local uid = player.UserId
	local now = tick()

	-- ── 1. Rate-limit ──────────────────────────────────────────────────────
	if _lastAttackTime[uid] and (now - _lastAttackTime[uid]) < SERVER_ATTACK_COOLDOWN then
		WeaponService.RecordViolation(player, "attack rate exceeded")
		return false, 0
	end
	_lastAttackTime[uid] = now

	-- ── 2. Damage ceiling ──────────────────────────────────────────────────
	local weaponId = EquippedWeapons[uid]
	local config = weaponId and WeaponRegistry.Get(weaponId)
	local baseDamage: number = (config and config.BaseDamage) or 10
	local maxAllowed = baseDamage * MAX_DAMAGE_MULTIPLIER
	local incoming: number = (hitData.Damage and tonumber(hitData.Damage)) or baseDamage

	if incoming > maxAllowed then
		WeaponService.RecordViolation(player, ("damage %d > max %d"):format(incoming, maxAllowed))
		-- Clamp rather than reject outright, so lag doesn't unfairly penalise
		incoming = maxAllowed
	end

	-- ── 3. Range check ─────────────────────────────────────────────────────
	if config and config.Range then
		local maxRange = config.Range + SERVER_RANGE_TOLERANCE
		local attackerChar = player.Character
		local attackerHRP = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?

		if attackerHRP and hitData.TargetName then
			local targetPlayer = game:GetService("Players"):FindFirstChild(hitData.TargetName :: string)
			local targetChar = targetPlayer and (targetPlayer :: Player).Character
			local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?

			if not targetHRP then
				-- Try dummy workspace model
				local dummyModel = workspace:FindFirstChild(hitData.TargetName :: string) :: Model?
				local dummyHRP = dummyModel and dummyModel:FindFirstChild("HumanoidRootPart") :: BasePart?
				targetHRP = dummyHRP
			end

			if targetHRP then
				local dist = (attackerHRP.Position - targetHRP.Position).Magnitude
				if dist > maxRange then
					WeaponService.RecordViolation(player,
						("range %.1f > max %.1f"):format(dist, maxRange))
					return false, 0
				end
			end
		end
	end

	return true, math.floor(incoming)
end

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

	-- Give the player a Tool instance so it appears in the hotbar.
	local config = WeaponRegistry.Get(weaponId)
	if config then
		_GiveTool(player, config)
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

	-- Remove the Tool from Backpack and Character.
	_RemoveTool(player, current)

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
	-- Wait for the Humanoid to exist — CharacterAdded fires before the
	-- character's children are all in place, so _GetHumanoid would return nil
	-- if we called EquipWeapon immediately.
	local character = player.Character
	if character then
		character:WaitForChild("Humanoid", 10)
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
		player.CharacterAdded:Connect(function(character)
			-- Run in a separate thread so WaitForChild doesn't block the signal.
			task.spawn(_EquipDefault, player)
		end)
		if player.Character then
			task.spawn(_EquipDefault, player)
		end
	end)

	-- Handle players already connected before this service loaded.
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			task.spawn(_EquipDefault, player)
		end)
		if player.Character then
			task.spawn(_EquipDefault, player)
		end
	end

	-- Clean up when a player leaves.
	Players.PlayerRemoving:Connect(function(player)
		EquippedWeapons[player.UserId] = nil
		_lastAttackTime[player.UserId] = nil
		_strikes[player.UserId]       = nil
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
