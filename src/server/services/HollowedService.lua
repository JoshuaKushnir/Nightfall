--!strict
--[[
	HollowedService.lua

	Issue #143: HollowedService — Ring 1 enemy with patrol, aggro, basic attack,
	            death, and Resonance grant.
	Epic: Phase 4 — World & Narrative

	Server-authoritative AI service for Hollowed enemies in Ring 1 (Verdant Shelf).

	Behaviour:
		• Patrol  — random wander within PatrolRadius of spawn, pause at waypoints
		• Aggro   — chase nearest player found within AggroRange
		• Attack  — melee swing when within AttackRange; applies HP + Posture damage
		• Dead    — visual death state, respawk after RespawnDelay

	Model:
		All body parts are anchored.  Movement is applied by shifting every part's
		CFrame each AI tick.  This avoids Roblox physics rig complexity for MVP.

	Registry integration:
		HollowedService.GetInstanceData(name) is called by CombatService so that
		player hitboxes can register damage against Hollowed models.

	Spawn:
		On Start(), one instance is spawned per Part tagged "HollowedSpawn" in
		CollectionService.  Placing tagged Parts in Ring 1 respects the zone boundary
		requirement; the service does not enforce it in code.

	Dependencies: ProgressionService, PostureService, StateService, NetworkProvider,
	              RunService, CollectionService, Players
]]

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local CollectionService  = game:GetService("CollectionService")
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local StateService     = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkProvider  = require(ReplicatedStorage.Shared.network.NetworkProvider)

-- Lazy-required to avoid load-order cycles
local ProgressionService: any = nil
local PostureService: any     = nil

local HollowedTypesModule = require(ReplicatedStorage.Shared.types.HollowedTypes)
type HollowedConfig = HollowedTypesModule.HollowedConfig
type HollowedData   = HollowedTypesModule.HollowedData
type HollowedState  = HollowedTypesModule.HollowedState

-- ─── Service ─────────────────────────────────────────────────────────────────

local HollowedService = {}
HollowedService._initialized = false

-- ─── Constants ───────────────────────────────────────────────────────────────

local AI_TICK_RATE       = 0.2   -- seconds between AI evaluations per NPC
local PATROL_ARRIVE_DIST = 2.0   -- studs — close enough to waypoint to stop
local PATROL_WAIT_TIME   = 2.0   -- seconds to idle at each waypoint
local CONFIRM_HIT_EVENT  = "HitConfirmed"
local NPC_HIT_DAMAGE_VAR = 0.10  -- ±10% attack damage variance (mirrors CombatService)

-- ─── Enemy Configs ───────────────────────────────────────────────────────────

--[[
	Registered Hollowed types.  Add new entries here to create new enemy variants.
	Placeholder values — spec-gap issue #129/130/131 pending art/balance pass.
]]
local CONFIGS: {[string]: HollowedConfig} = {
	basic_hollowed = {
		Id             = "basic_hollowed",
		DisplayName    = "Hollowed",
		MaxHealth      = 80,
		AttackDamage   = 12,
		PostureDamage  = 18,
		AggroRange     = 30,
		AttackRange    = 5,
		PatrolRadius   = 20,
		MoveSpeed      = 8,
		AttackCooldown = 2.0,
		ResonanceGrant = 25,  -- matches Kill_Enemy rate (spec-gap placeholder)
		RespawnDelay   = 12,
		BodyColor      = BrickColor.new("Dark stone grey"),
	},
}

-- ─── State ───────────────────────────────────────────────────────────────────

local _instances: {[string]: HollowedData}  = {}
local _models:    {[string]: Model}         = {}
local _nextId     = 0
local _heartbeatConn: RBXScriptConnection?  = nil

-- ─── Private — Model ─────────────────────────────────────────────────────────

--[[
	Build a simple anchored R6-like humanoid rig for a Hollowed enemy.
	All parts are anchored; movement is done by shifting CFrames in the AI loop.
	Returns the created Model and the HumanoidRootPart.
]]
local function _CreateModel(instanceId: string, config: HollowedConfig, spawnCF: CFrame): (Model, BasePart)
	local model   = Instance.new("Model")
	model.Name    = instanceId

	local origin = spawnCF.Position
	local color  = config.BodyColor

	-- Helper: create a colour-matched anchored body part
	local function makePart(name: string, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name       = name
		p.Size       = size
		p.CFrame     = CFrame.new(origin + offset)
		p.Anchored   = true
		p.CanCollide = (name ~= "HumanoidRootPart")
		p.BrickColor = color
		p.Material   = Enum.Material.SmoothPlastic
		if name == "HumanoidRootPart" then
			p.Transparency = 1
			p.CanCollide   = false
		end
		p.Parent = model
		return p
	end

	-- Body parts (root at pelvis height ~= 0)
	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1),      Vector3.new(0,    0,    0))
	makePart("Torso",     Vector3.new(2, 2, 1),      Vector3.new(0,    1.5,  0))
	makePart("Head",      Vector3.new(1, 1, 1),       Vector3.new(0,    3,    0))
	makePart("LeftArm",   Vector3.new(1, 2, 1),       Vector3.new(-1.5, 1.5,  0))
	makePart("RightArm",  Vector3.new(1, 2, 1),       Vector3.new( 1.5, 1.5,  0))
	makePart("LeftLeg",   Vector3.new(1, 2, 1),       Vector3.new(-0.5, -0.5, 0))
	makePart("RightLeg",  Vector3.new(1, 2, 1),       Vector3.new( 0.5, -0.5, 0))

	-- Health billboard above head
	local head: BasePart? = model:FindFirstChild("Head") :: BasePart?
	if head then
		local billboard         = Instance.new("BillboardGui")
		billboard.Name          = "HollowedHUD"
		billboard.Adornee       = head
		billboard.Size          = UDim2.new(0, 120, 0, 40)
		billboard.StudsOffset   = Vector3.new(0, 2.5, 0)
		billboard.AlwaysOnTop   = false
		billboard.Parent        = model

		local nameLabel            = Instance.new("TextLabel")
		nameLabel.Name             = "NameLabel"
		nameLabel.Size             = UDim2.new(1, 0, 0.5, 0)
		nameLabel.Position         = UDim2.new(0, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3       = Color3.fromRGB(220, 80, 80)
		nameLabel.TextScaled       = true
		nameLabel.Font             = Enum.Font.GothamBold
		nameLabel.Text             = config.DisplayName
		nameLabel.Parent           = billboard

		local hpBar               = Instance.new("Frame")
		hpBar.Name                = "HealthBar"
		hpBar.BackgroundColor3    = Color3.fromRGB(210, 45, 45)
		hpBar.BorderSizePixel     = 0
		hpBar.Size                = UDim2.new(1, 0, 0.3, 0)
		hpBar.Position            = UDim2.new(0, 0, 0.65, 0)
		hpBar.Parent              = billboard
	end

	model.Parent   = Workspace
	model.PrimaryPart = root :: PVInstance

	return model, root :: BasePart
end

--[[
	Recolour all visible body parts and update the health bar fraction.
]]
local function _UpdateVisuals(instanceId: string)
	local data  = _instances[instanceId]
	local model = _models[instanceId]
	if not data or not model then return end

	local hpFrac = math.clamp(data.CurrentHealth / data.MaxHealth, 0, 1)
	local col    = if data.State == "Dead" then BrickColor.new("Medium stone grey") else
	               if data.State == "Aggro" or data.State == "Attacking" then BrickColor.new("Bright red") else
	               BrickColor.new("Dark stone grey")

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			(part :: BasePart).BrickColor = col
		end
	end

	-- Update health bar width
	local billboard = model:FindFirstChild("HollowedHUD", true)
	local hpBar     = billboard and billboard:FindFirstChild("HealthBar")
	if hpBar and hpBar:IsA("Frame") then
		(hpBar :: Frame).Size = UDim2.new(hpFrac, 0, 0.3, 0)
	end
end

-- ─── Private — Movement ──────────────────────────────────────────────────────

--[[
	Move all anchored parts in the model by `delta` studs.
	Also rotates the model to face the XZ direction of `faceDir` if provided.
]]
local function _MoveModel(model: Model, delta: Vector3, facePos: Vector3?)
	-- Compute optional yaw rotation
	local rotDelta: CFrame? = nil
	if facePos then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local origin  = root.Position
			local flatDir = Vector3.new(facePos.X - origin.X, 0, facePos.Z - origin.Z)
			if flatDir.Magnitude > 0.01 then
				local newLook  = CFrame.lookAt(origin, origin + flatDir)
				-- Extract just the rotation difference (ignore position offset)
				rotDelta = newLook * root.CFrame:Inverse()
			end
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part :: BasePart).Anchored then
			local p = part :: BasePart
			if rotDelta then
				p.CFrame = rotDelta * p.CFrame + delta
			else
				p.CFrame = p.CFrame + delta
			end
		end
	end
end

-- ─── Private — AI ────────────────────────────────────────────────────────────

--[[
	Returns the nearest Player whose character is within `maxRange` studs of
	`origin`, ignoring dead characters.  Returns nil if none found.
]]
local function _GetNearestPlayer(origin: Vector3, maxRange: number): Player?
	local bestPlayer: Player?  = nil
	local bestDist             = maxRange + 1

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local data = StateService:GetPlayerData(player)
		if data and data.State == "Dead" then continue end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end
		local dist = (root.Position - origin).Magnitude
		if dist < bestDist then
			bestDist   = dist
			bestPlayer = player
		end
	end

	return bestPlayer
end

--[[
	Pick a random patrol waypoint within `radius` studs of `spawnPos` at the
	same Y height (NPCs don't climb).
]]
local function _RandomPatrolPoint(spawnPos: Vector3, radius: number): Vector3
	local angle  = math.random() * math.pi * 2
	local dist   = math.random() * radius
	return Vector3.new(
		spawnPos.X + math.cos(angle) * dist,
		spawnPos.Y,
		spawnPos.Z + math.sin(angle) * dist
	)
end

--[[
	Apply melee damage from this Hollowed instance to `targetPlayer`.
	Handles HP subtraction and posture gain.  Sets player Dead if HP reaches 0.
	Broadcasts HitConfirmed event to all clients.
]]
local function _AttackPlayer(data: HollowedData, targetPlayer: Player)
	local config = CONFIGS[data.ConfigId]
	if not config then return end

	-- Validate target still alive and not in iframes
	local targetData = StateService:GetPlayerData(targetPlayer)
	if not targetData then return end
	if targetData.State == "Dead" or targetData.State == "Dodging" then return end

	-- Damage variance ±10% (mirrors CombatService._ApplyDamageVariance)
	local variance    = config.AttackDamage * NPC_HIT_DAMAGE_VAR
	local finalDamage = math.floor(
		math.random(math.floor(config.AttackDamage - variance), math.ceil(config.AttackDamage + variance))
	)

	-- Apply posture pressure (enemy hit on unblocked player drains posture)
	if PostureService then
		PostureService.DrainPosture(targetPlayer, config.PostureDamage, "NPC")
	end

	-- Apply HP damage
	targetData.Health.Current = math.max(0, targetData.Health.Current - finalDamage)
	print(("[HollowedService] %s attacked %s for %d HP"):format(data.InstanceId, targetPlayer.Name, finalDamage))

	-- Check player death
	if targetData.Health.Current <= 0 then
		StateService:SetPlayerState(targetPlayer, "Dead")
		print(("[HollowedService] %s killed %s"):format(data.InstanceId, targetPlayer.Name))
	end

	-- Broadcast hit feedback (treats NPC as "attacker name" string)
	local hitEvent = NetworkProvider:GetRemoteEvent(CONFIRM_HIT_EVENT)
	if hitEvent then
		-- Fire using attacker=nil pattern; clients receive instanceId as the attacker identifier
		hitEvent:FireAllClients(nil, targetPlayer, finalDamage, false, false)
	end
end

--[[
	Evaluate AI for a single Hollowed instance.  Called every AI_TICK_RATE seconds.
]]
local function _TickAI(instanceId: string, dt: number)
	local data   = _instances[instanceId]
	local model  = _models[instanceId]
	local config = CONFIGS[data.ConfigId]
	if not data or not model or not config then return end
	if not data.IsActive or data.State == "Dead" then return end

	local now          = tick()
	local rootPart     = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local rootPos = rootPart.Position
	data.RootPosition = rootPos

	-- ── Aggro detection ──────────────────────────────────────────────────────

	local nearestPlayer = _GetNearestPlayer(rootPos, config.AggroRange)

	if nearestPlayer and data.State ~= "Attacking" then
		if data.State ~= "Aggro" then
			data.State = "Aggro"
			data.Target = nearestPlayer
			_UpdateVisuals(instanceId)
			print(("[HollowedService] %s → Aggro on %s"):format(instanceId, nearestPlayer.Name))
		end
		data.Target = nearestPlayer
	elseif not nearestPlayer and data.State == "Aggro" then
		data.State        = "Patrol"
		data.Target       = nil
		data.PatrolTarget = nil
		_UpdateVisuals(instanceId)
		print(("[HollowedService] %s → Patrol (target lost)"):format(instanceId))
	end

	-- ── State behaviour ──────────────────────────────────────────────────────

	if data.State == "Aggro" and data.Target then
		local target    = data.Target
		local targetChar = target.Character
		if not targetChar then
			data.State  = "Patrol"
			data.Target = nil
			return
		end
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not targetRoot then return end

		local toTarget = targetRoot.Position - rootPos
		local dist     = toTarget.Magnitude

		if dist <= config.AttackRange then
			-- Within attack range
			if now - data.LastAttackTick >= config.AttackCooldown then
				data.State = "Attacking"
				data.LastAttackTick = now
				_UpdateVisuals(instanceId)
				_AttackPlayer(data, target)
				-- Return to Aggro after a brief pause (handled next tick)
				task.delay(0.5, function()
					if _instances[instanceId] and _instances[instanceId].State == "Attacking" then
						_instances[instanceId].State = "Aggro"
						_UpdateVisuals(instanceId)
					end
				end)
			end
		else
			-- Move toward player
			local stepDir = toTarget.Unit
			local stepVec = stepDir * config.MoveSpeed * dt
			_MoveModel(model, stepVec, targetRoot.Position)
		end

	elseif data.State == "Patrol" then
		-- Idle at waypoint: wait before picking next
		if now < data.PatrolWaitUntil then return end

		-- Pick a new waypoint if we don't have one (or just arrived)
		if not data.PatrolTarget then
			data.PatrolTarget = _RandomPatrolPoint(data.SpawnCFrame.Position, config.PatrolRadius)
		end

		local toWaypoint: Vector3 = data.PatrolTarget - rootPos
		local distWaypoint        = toWaypoint.Magnitude

		if distWaypoint <= PATROL_ARRIVE_DIST then
			-- Arrived — idle for a bit then pick another waypoint
			data.PatrolTarget    = nil
			data.PatrolWaitUntil = now + PATROL_WAIT_TIME
		else
			local stepDir = toWaypoint.Unit
			local stepVec = stepDir * (config.MoveSpeed * 0.5) * dt  -- patrol at half speed
			_MoveModel(model, stepVec, data.PatrolTarget)
		end
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Spawn a new Hollowed instance of the given config type at spawnCF.
	Returns the instanceId, or nil if configId is unknown.
]]
function HollowedService.SpawnInstance(configId: string, spawnCF: CFrame): string?
	local config = CONFIGS[configId]
	if not config then
		warn(("[HollowedService] Unknown configId: %s"):format(configId))
		return nil
	end

	_nextId += 1
	local instanceId = ("Hollowed_%d"):format(_nextId)

	local model, _ = _CreateModel(instanceId, config, spawnCF)
	_models[instanceId] = model

	local data: HollowedData = {
		InstanceId      = instanceId,
		ConfigId        = configId,
		SpawnCFrame     = spawnCF,
		RootPosition    = spawnCF.Position,
		CurrentHealth   = config.MaxHealth,
		MaxHealth       = config.MaxHealth,
		State           = "Patrol",
		Target          = nil,
		LastAttackTick  = 0,
		PatrolTarget    = nil,
		PatrolWaitUntil = 0,
		LastAITick      = 0,
		KillerId        = nil,
		IsActive        = true,
	}
	_instances[instanceId] = data

	print(("[HollowedService] Spawned %s (%s) at %s"):format(instanceId, configId, tostring(spawnCF.Position)))
	return instanceId
end

--[[
	Despawn and permanently remove a Hollowed instance.
]]
function HollowedService.DespawnInstance(instanceId: string)
	local model = _models[instanceId]
	if model then
		model:Destroy()
		_models[instanceId] = nil :: any
	end
	_instances[instanceId] = nil :: any
	print(("[HollowedService] Despawned %s"):format(instanceId))
end

--[[
	Apply hit damage to a Hollowed instance (called by CombatService).
	attacker: the Player who landed the hit.
	Returns true if still alive, false if just killed.
]]
function HollowedService.ApplyDamage(instanceId: string, damage: number, attacker: Player?): boolean
	local data   = _instances[instanceId]
	local config = data and CONFIGS[data.ConfigId]
	if not data or not config or not data.IsActive then return false end
	if data.State == "Dead" then return false end

	data.CurrentHealth = math.max(0, data.CurrentHealth - damage)
	_UpdateVisuals(instanceId)

	print(("[HollowedService] %s took %d damage — HP %d/%d"):format(
		instanceId, damage, data.CurrentHealth, data.MaxHealth
	))

	if data.CurrentHealth <= 0 then
		-- Record killer
		data.KillerId = attacker and attacker.UserId or nil
		data.State    = "Dead"
		data.IsActive = false
		data.Target   = nil
		_UpdateVisuals(instanceId)

		print(("[HollowedService] %s died — granting %d Resonance to killer"):format(
			instanceId, config.ResonanceGrant
		))

		-- Grant Resonance to the killing player
		if attacker and ProgressionService then
			ProgressionService.GrantResonance(attacker, config.ResonanceGrant, "Hollowed")
		end

		-- Schedule respawn
		task.delay(config.RespawnDelay, function()
			if _instances[instanceId] then
				-- Reset health and state, re-activate
				data.CurrentHealth   = config.MaxHealth
				data.MaxHealth       = config.MaxHealth
				data.State           = "Patrol"
				data.Target          = nil
				data.PatrolTarget    = nil
				data.PatrolWaitUntil = 0
				data.KillerId        = nil
				data.IsActive        = true
				-- Teleport model back to spawn
				local model = _models[instanceId]
				if model then
					local spawnPos = data.SpawnCFrame.Position
					local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
					if rootPart then
						local offset = spawnPos - rootPart.Position
						_MoveModel(model, offset, nil)
					end
				end
				_UpdateVisuals(instanceId)
				print(("[HollowedService] %s respawned at spawn point"):format(instanceId))
			end
		end)

		return false
	end

	return true
end

--[[
	Read-only access to instance data.
	Called by CombatService to identify Hollowed as a valid hit target.
]]
function HollowedService.GetInstanceData(instanceId: string): HollowedData?
	return _instances[instanceId]
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function HollowedService:Init(dependencies: {[string]: any}?)
	print("[HollowedService] Initializing...")
	if dependencies then
		ProgressionService = dependencies.ProgressionService
		PostureService     = (dependencies :: any).PostureService
	end
	HollowedService._initialized = true
	print("[HollowedService] Initialized")
end

function HollowedService:Start()
	print("[HollowedService] Starting...")
	assert(HollowedService._initialized, "[HollowedService] Must call Init() before Start()")

	-- Lazy-require PostureService if not injected (avoids load-order issues)
	if not PostureService then
		local ok, svc = pcall(require, game:GetService("ServerScriptService").Server.services.PostureService)
		if ok then PostureService = svc end
	end

	-- Spawn one instance at every Part tagged "HollowedSpawn" in Workspace
	local spawnParts = CollectionService:GetTagged("HollowedSpawn")
	if #spawnParts == 0 then
		warn("[HollowedService] No parts tagged 'HollowedSpawn' found — no Hollowed spawned. Tag Parts in Ring 1 to populate.")
	end

	for _, part in spawnParts do
		if part:IsA("BasePart") then
			local spawnCF = (part :: BasePart).CFrame
			HollowedService.SpawnInstance("basic_hollowed", spawnCF)
		end
	end

	-- AI loop — evaluate each instance every AI_TICK_RATE seconds
	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		local now = tick()
		for instanceId, data in _instances do
			if now - data.LastAITick >= AI_TICK_RATE then
				data.LastAITick = now
				local ok, err = pcall(_TickAI, instanceId, AI_TICK_RATE)
				if not ok then
					warn(("[HollowedService] AI tick error for %s: %s"):format(instanceId, tostring(err)))
				end
			end
		end
	end)

	print("[HollowedService] Started — AI loop active")
end

function HollowedService:Shutdown()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end
	for instanceId in _instances do
		HollowedService.DespawnInstance(instanceId)
	end
	print("[HollowedService] Shutdown complete")
end

return HollowedService
