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
local TweenService       = game:GetService("TweenService")
local AnimationDatabase  = require(ReplicatedStorage.Shared.AnimationDatabase)
local HitboxService    = require(ReplicatedStorage.Shared.modules.HitboxService)
local DummyService      = require(script.Parent.DummyService)

local StateService     = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkProvider  = require(ReplicatedStorage.Shared.network.NetworkProvider)
local SpawnerConfig    = require(game:GetService("ServerScriptService").Server.modules.SpawnerConfig)

-- Lazy-required to avoid load-order cycles
local ProgressionService: any = nil
local PostureService: any     = nil

local HollowedTypesModule = require(ReplicatedStorage.Shared.types.HollowedTypes)
type HollowedConfig = HollowedTypesModule.HollowedConfig
type HollowedData   = HollowedTypesModule.HollowedData
type HollowedState  = HollowedTypesModule.HollowedState
type SpawnZone = SpawnerConfig.SpawnZone

-- ─── Service ─────────────────────────────────────────────────────────────────

local HollowedService = {}
HollowedService._initialized = false

-- ─── Constants ───────────────────────────────────────────────────────────────

local BASE_AI_TICK       = 0.18  -- base AI tick rate; scaled by difficulty
local AI_TICK_RATE       = 0.2   -- seconds between AI evaluations per NPC
local PATROL_ARRIVE_DIST = 2.0   -- studs — close enough to waypoint to stop
local PATROL_WAIT_TIME   = 2.0   -- seconds to idle at each waypoint
local CONFIRM_HIT_EVENT  = "HitConfirmed"
local NPC_HIT_DAMAGE_VAR = 0.10  -- ±10% attack damage variance (mirrors CombatService)

-- ─── Difficulty Scaling Helpers ──────────────────────────────────────────────

--[[
	Get AI tick rate scaled by difficulty.
	Higher difficulty = faster ticks (lower tick interval).
	Difficulty range: 1–10 typically.
]]
local function GetAITickForDiff(diff: number): number
	return BASE_AI_TICK - 0.06 * (diff / 10)
end

-- ─── Enemy Configs ───────────────────────────────────────────────────────────

--[[
	Registered Hollowed types.  Add new entries here to create new enemy variants.
	Placeholder values — spec-gap issue #129/130/131 pending art/balance pass.
]]
local CONFIGS: {[string]: HollowedConfig} = {
	basic_hollowed = {
		Id             = "basic_hollowed",
		DisplayName    = "Wayward Hollowed",
		MaxHealth      = 80,
		MaxPoise       = 100,
		AttackDamage   = 12,
		PostureDamage  = 18,
		AggroRange     = 30,
		AttackRange    = 5,
		PatrolRadius   = 20,
		MoveSpeed      = 8,
		AttackCooldown = 2.0,
		ResonanceGrant = 25,
		RespawnDelay   = 12,
		BodyColor      = BrickColor.new("Dark stone grey"),
	},
	ironclad_hollowed = {
		Id             = "ironclad_hollowed",
		DisplayName    = "Ironclad Hollowed",
		MaxHealth      = 150,
		MaxPoise       = 250,
		AttackDamage   = 20,
		PostureDamage  = 40,
		AggroRange     = 25,
		AttackRange    = 6,
		PatrolRadius   = 15,
		MoveSpeed      = 6,
		AttackCooldown = 3.5,
		ResonanceGrant = 50,
		RespawnDelay   = 20,
		BodyColor      = BrickColor.new("Black"),
	},
	silhouette_hollowed = {
		Id             = "silhouette_hollowed",
		DisplayName    = "Silhouette",
		MaxHealth      = 60,
		MaxPoise       = 80,
		AttackDamage   = 15,
		PostureDamage  = 10,
		AggroRange     = 35,
		AttackRange    = 4,
		PatrolRadius   = 25,
		MoveSpeed      = 14,
		AttackCooldown = 1.5,
		ResonanceGrant = 35,
		RespawnDelay   = 15,
		BodyColor      = BrickColor.new("Ghost grey"),
	},
	resonant_hollowed = {
		Id             = "resonant_hollowed",
		DisplayName    = "Resonant Hollowed",
		MaxHealth      = 75,
		MaxPoise       = 60,
		AttackDamage   = 25,
		PostureDamage  = 15,
		AggroRange     = 40,
		AttackRange    = 20,
		PatrolRadius   = 20,
		MoveSpeed      = 7,
		AttackCooldown = 4.0,
		ResonanceGrant = 60,
		RespawnDelay   = 15,
		BodyColor      = BrickColor.new("Bright violet"),
	},
	ember_hollowed = {
		Id             = "ember_hollowed",
		DisplayName    = "Ember Hollowed",
		MaxHealth      = 200,
		MaxPoise       = 300,
		AttackDamage   = 30,
		PostureDamage  = 50,
		AggroRange     = 35,
		AttackRange    = 8,
		PatrolRadius   = 25,
		MoveSpeed      = 10,
		AttackCooldown = 2.5,
		ResonanceGrant = 100,
		RespawnDelay   = 30,
		BodyColor      = BrickColor.new("Deep orange"),
	},
}

-- ─── State ───────────────────────────────────────────────────────────────────

local _instances: {[string]: HollowedData}  = {}
local _models:    {[string]: Model}         = {}
local _animStates: {[string]: string}       = {}
local _nextId     = 0
local _heartbeatConn: RBXScriptConnection?  = nil
local _spawnerConfig: SpawnerConfig.SpawnerConfig = SpawnerConfig.GetDefaultConfig()
local _lastSpawnCheckTime: number = 0
local _instanceAreaMap: {[string]: string} = {}  -- Maps instanceId -> areaName for mob cap tracking

-- ─── Private — Model ─────────────────────────────────────────────────────────

--[[
	Build a simple anchored R6-like humanoid rig for a Hollowed enemy.
	All parts are anchored; movement is done by shifting CFrames in the AI loop.
	Returns the created Model and the HumanoidRootPart.
]]
local function _RigModel(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	if not root or not torso then return end

	local function makeJoint(name, part0, part1, c0, c1)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = c0
		m.C1 = c1
		m.Parent = part0
	end

	-- Standard R6 joints
	makeJoint("RootJoint", root, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0))

	local head = model:FindFirstChild("Head")
	if head then
		makeJoint("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0))
	end

	local lArm = model:FindFirstChild("Left Arm")
	if lArm then
		makeJoint("Left Shoulder", torso, lArm, CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0))
	end

	local rArm = model:FindFirstChild("Right Arm")
	if rArm then
		makeJoint("Right Shoulder", torso, rArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0))
	end

	local lLeg = model:FindFirstChild("Left Leg")
	if lLeg then
		makeJoint("Left Hip", torso, lLeg, CFrame.new(-1, -1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0))
	end

	local rLeg = model:FindFirstChild("Right Leg")
	if rLeg then
		makeJoint("Right Hip", torso, rLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0))
	end
end

local function _CreateModel(instanceId: string, config: HollowedConfig, spawnCF: CFrame): (Model, BasePart)
	local model   = Instance.new("Model")
	model.Name    = instanceId

	local origin = spawnCF.Position
	local color  = config.BodyColor

	-- Helper: create a colour-matched body part
	local function makePart(name: string, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name       = name
		p.Size       = size
		p.CFrame     = CFrame.new(origin + offset)
		p.Anchored   = false
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
	makePart("Left Arm",  Vector3.new(1, 2, 1),       Vector3.new(-1.5, 1.5,  0))
	makePart("Right Arm", Vector3.new(1, 2, 1),       Vector3.new( 1.5, 1.5,  0))
	makePart("Left Leg",  Vector3.new(1, 2, 1),       Vector3.new(-0.5, -0.5, 0))
	makePart("Right Leg", Vector3.new(1, 2, 1),       Vector3.new( 0.5, -0.5, 0))

	-- Humanoid for animations
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = config.MaxHealth
	humanoid.Health = config.MaxHealth
	humanoid.WalkSpeed = config.MoveSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	_RigModel(model)

	-- Play Idle animation
	local animator = humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = AnimationDatabase.Movement.Idle
	local track = animator:LoadAnimation(idleAnim)
	track.Looped = true
	track:Play()

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
	Walk the model towards a target using Humanoid:MoveTo.
]]
local function _WalkTo(model: Model, targetPos: Vector3)
	local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid:MoveTo(targetPos)
	end
end

--[[
	Instantly move the model by `delta` studs.
	Also rotates the model to face the XZ direction of `facePos` if provided.
]]
local function _PivotModel(model: Model, delta: Vector3, facePos: Vector3?)
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local newCF = root.CFrame + delta
	if facePos then
		local flatDir = Vector3.new(facePos.X - root.Position.X, 0, facePos.Z - root.Position.Z)
		if flatDir.Magnitude > 0.01 then
			newCF = CFrame.lookAt(newCF.Position, newCF.Position + flatDir)
		end
	end
	model:PivotTo(newCF)
end

-- ─── Private — AI ────────────────────────────────────────────────────────────

--[[
	Returns the best Player target whose character is within `maxRange` studs of
	`origin`, ignoring dead characters.  Returns nil if none found.
]]
local function _GetBestTarget(origin: Vector3, maxRange: number, focusTargeting: number): Player?
	local bestPlayer: Player? = nil
	local bestScore = -math.huge

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local data = StateService:GetPlayerData(player)
		if data and data.State == "Dead" then continue end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end

		local dist = (root.Position - origin).Magnitude
		if dist <= maxRange then
			local distScore = -dist
			local hpScore = 0
			if data then
				local hpFrac = (data.CurrentHealth or 100) / (data.MaxHealth or 100)
				hpScore = (1 - hpFrac) * 30 * focusTargeting
			end

			local total = distScore + hpScore
			if total > bestScore then
				bestScore = total
				bestPlayer = player
			end
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
	Set the loop animation state (Idle vs Run) for a mob.
	Only changes if the new state is different from current.
]]
local function _SetAnimState(instanceId: string, model: Model, state: "Idle" | "Run")
	if _animStates[instanceId] == state then return end
	_animStates[instanceId] = state

	local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator") :: Animator?
	if not animator then return end

	-- Stop running tracks that match movement
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation.AnimationId == AnimationDatabase.Movement.Idle or
		   track.Animation.AnimationId == AnimationDatabase.Movement.Run then
			track:Stop(0.2)
		end
	end

	local animId = (state == "Run") and AnimationDatabase.Movement.Run or AnimationDatabase.Movement.Idle
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = animator:LoadAnimation(anim)
	track.Looped = true
	track:Play(0.2)
end

--[[
	Play a standard R6 animation on the humanoid.
	@param model - The Hollowed model
	@param attackType - Type of attack (e.g. "melee")
	@param duration - Total animation duration in seconds
]]
local function _PlayAttackAnimation(model: Model, configId: string, duration: number)
	local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator") :: Animator?
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Pick animation ID from database based on variant
	local animId = AnimationDatabase.Combat.General.Punch1 -- Default

	if configId == "silhouette_hollowed" then
		animId = AnimationDatabase.Combat.Aspect.Ash.AshenStep
	elseif configId == "resonant_hollowed" then
		animId = AnimationDatabase.Combat.Aspect.Gale.WindStrike
	elseif configId == "ember_hollowed" then
		animId = AnimationDatabase.Combat.Aspect.Ember.Surge
	else
		-- basic_hollowed, ironclad_hollowed (or default)
		local punches = {
			AnimationDatabase.Combat.General.Punch1,
			AnimationDatabase.Combat.General.Punch2,
			AnimationDatabase.Combat.General.Punch3,
			AnimationDatabase.Combat.General.LeftHit,
			AnimationDatabase.Combat.General.RightHit
		}
		animId = punches[math.random(1, #punches)]
	end

	-- Fallback if the aspect animation is a stub
	if animId == "" or animId == "rbxassetid://0" then
		animId = AnimationDatabase.Combat.General.Punch1
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local track = animator:LoadAnimation(animation)
	track:Play()
end

--[[
	Apply melee damage from this Hollowed instance to `targetPlayer`.
	Handles HP subtraction and posture gain.  Sets player Dead if HP reaches 0.
	Broadcasts HitConfirmed event to all clients.
]]
local function _ExecuteHitboxAttack(data: HollowedData, model: Model, config: HollowedConfig, shape: "Box" | "Sphere", size: Vector3, offset: Vector3, duration: number)
	data.State = "Attacking"
	data.LastAttackTick = tick()
	_UpdateVisuals(data.InstanceId)

	-- Play attack animation before executing hitbox
	_PlayAttackAnimation(model, data.ConfigId, duration)

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local hitboxConfig = {
		Shape = shape,
		Owner = data.InstanceId,
		Damage = config.AttackDamage,
		PostureDamage = config.PostureDamage,
		Position = (root.CFrame * CFrame.new(offset)).Position,
		CFrame = root.CFrame * CFrame.new(offset),
		Size = size,
		Radius = size.X, -- Assuming uniform if sphere
		Duration = duration,
	}

	-- Trigger hitbox logic. Create the hitbox, attach server-side OnHit to apply damage,
	-- then immediately evaluate collisions via TestHitbox so server-controlled NPC attacks
	-- apply damage to players/dummies reliably.
	local hb = HitboxService.CreateHitbox(hitboxConfig)

	-- Attach OnHit to route damage into player/dummy damage pipelines
	do
		local origOnHit = hb.Config.OnHit
		hb.Config.OnHit = function(target: any, hitData: any)
			-- Preserve original callback behavior if present
			if origOnHit then
				pcall(origOnHit, target, hitData)
			end

			-- Resolve target and apply damage via the IncomingHPDamage attribute for players,
			-- or DummyService.ApplyDamage for dummies (server-side canonical path).
			local dmg = hb.Config.Damage or config.AttackDamage or 0
			local post = hb.Config.PostureDamage or config.PostureDamage or 0

			-- Player target
			if typeof(target) == "Instance" and target:IsA("Player") then
				local ply = target :: Player
				local char = ply.Character
				if char and char.Parent then
					local targetState = StateService:GetPlayerData(ply)
					local isBlocking = targetState and targetState.State == "Blocking"

					if isBlocking then
						-- Target is blocking, apply only posture damage
						local existingP = (char:GetAttribute("IncomingPostureDamage") or 0) :: number
						char:SetAttribute("IncomingPostureDamage", existingP + post)
						char:SetAttribute("IncomingPostureDamageSource", (data and data.InstanceId or "Hollowed") .. "_Attack")
					else
						-- Target not blocking, apply only HP damage
						local existing = (char:GetAttribute("IncomingHPDamage") or 0) :: number
						char:SetAttribute("IncomingHPDamage", existing + dmg)
						char:SetAttribute("IncomingHPDamageSource", (data and data.InstanceId or "Hollowed") .. "_Attack")
					end
				end

			-- Dummy target (string identifier)
			elseif type(target) == "string" then
				local dummyId = target
				-- Ensure DummyService exists and apply direct damage
				if DummyService and DummyService.ApplyDamage then
					pcall(function()
						DummyService.ApplyDamage(dummyId, dmg)
					end)
				end
			end
		end
	end

	-- Immediately test the hitbox to invoke OnHit for current frame
	HitboxService.TestHitbox(hb)

	-- Lock in attack state for cooldown, then resume
	task.delay(duration + 0.5, function()
		if _instances[data.InstanceId] and _instances[data.InstanceId].State == "Attacking" then
			_instances[data.InstanceId].State = "Aggro"
			_UpdateVisuals(data.InstanceId)
		end
	end)
end



--[[
	Try to execute an attack if cooldown is ready and target is in range.
	Scales attack cooldown by difficulty.
	Returns true if attack was executed, false otherwise.
]]
local function _TryAttack(data: HollowedData, model: Model, config: HollowedConfig, targetRoot: BasePart, now: number): boolean
	local rootPos = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart).Position
	local dist = (targetRoot.Position - rootPos).Magnitude

	-- Check if in attack range
	if dist > config.AttackRange then
		return false
	end

	-- Difficulty-scaled cooldown: 1.1 - 0.3 * diffNorm
	local diff = data.Difficulty or 1
	local diffNorm = math.clamp(diff / 10, 0, 1)
	local cdScale = 1.1 - 0.3 * diffNorm
	local effectiveCooldown = config.AttackCooldown * cdScale

	-- Check if cooldown is ready
	if now - data.LastAttackTick < effectiveCooldown then
		return false
	end

	-- Execute the attack with brief windup
	task.delay(0.18, function()
		if _instances[data.InstanceId] and _instances[data.InstanceId].State == "Aggro" then
			_ExecuteHitboxAttack(data, model, config, "Box", Vector3.new(4, 4, 4), Vector3.new(0, 0, -3), 0.3)
		end
	end)

	return true
end

--[[
	Execute the specific custom AI move set per variant instead of just swinging.
	Includes prediction for moving targets and Humanoid:Move micro-adjustments.
]]
local function _ExecuteVariantAI(data: HollowedData, model: Model, config: HollowedConfig, dt: number, targetRoot: BasePart, now: number)
	local rootPos = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart).Position

	-- ── Target prediction ────────────────────────────────────────────────────
	local targetVel = targetRoot.AssemblyLinearVelocity
	local diff = data.Difficulty or 1
	local diffNorm = math.clamp(diff / 10, 0, 1)
	local leadTime = 0.2 + 0.2 * diffNorm
	local predictedPos = targetRoot.Position + targetVel * leadTime

	local toTarget = predictedPos - rootPos
	local dist = toTarget.Magnitude
	local hasFacingDir = toTarget.Magnitude > 0.01

	-- Always keep Hollowed oriented toward the live target while engaged.
	if hasFacingDir then
		_PivotModel(model, Vector3.zero, targetRoot.Position)
	end

	local aggro = data.FocusAggression or 1
	local def = data.FocusDefense or 1

	if data.ConfigId == "basic_hollowed" then
		local desiredMin = config.AttackRange * 0.7
		local desiredMax = config.AttackRange * 1.1

		-- Try to attack if conditions met
		if dist <= config.AttackRange and math.random() < 0.25 + aggro * 0.5 then
			_TryAttack(data, model, config, targetRoot, now)
			_SetAnimState(data.InstanceId, model, "Idle")
		else
			-- Movement with Humanoid:Move micro-adjustments
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then
				local dir = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, -1)

				if dist > desiredMax then
					-- Chase: move toward predicted position
					humanoid:Move(dir, true)
					_SetAnimState(data.InstanceId, model, "Run")
				elseif dist < desiredMin then
					-- Back up away from target
					humanoid:Move(-dir, true)
					_SetAnimState(data.InstanceId, model, "Run")
				else
					-- Strafe around target
					local side = math.random() < 0.5 and dir:Cross(Vector3.yAxis()) or Vector3.yAxis():Cross(dir)
					side = side.Unit
					local strafeMag = 5 + 5 * aggro
					humanoid:Move(side * math.clamp(strafeMag * dt, -4, 4), true)
					_SetAnimState(data.InstanceId, model, "Run")
				end
			end
		end

	elseif data.ConfigId == "ironclad_hollowed" then
		-- Ironclad: occasionally blocks while moving, heavy slam
		if dist <= config.AttackRange then
			_TryAttack(data, model, config, targetRoot, now)
			_SetAnimState(data.InstanceId, model, "Idle")
		else
			-- Move forward with Humanoid:Move
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then
				local dir = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, -1)
				humanoid:Move(dir, true)
			end
			_SetAnimState(data.InstanceId, model, "Run")
			-- Randomly block
			if math.random() < (0.05 * def) and data.State ~= "Blocking" then
				data.State = "Blocking"
				task.delay(1.5, function() if _instances[data.InstanceId] and _instances[data.InstanceId].State == "Blocking" then _instances[data.InstanceId].State = "Aggro" end end)
			end
		end

	elseif data.ConfigId == "silhouette_hollowed" then
		-- Silhouette: Stays just out of reach, dashes in
		if dist > config.AttackRange and dist < 12 and _TryAttack(data, model, config, targetRoot, now) then
			-- Dash attack: move into range before hitting
			_PivotModel(model, toTarget.Unit * 8, targetRoot.Position)
			_SetAnimState(data.InstanceId, model, "Run")
		elseif dist <= config.AttackRange then
			-- Back up with Humanoid:Move
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then
				local dir = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, -1)
				humanoid:Move(-dir, true)
			end
			_SetAnimState(data.InstanceId, model, "Run")
		else
			-- Chase / circle with Humanoid:Move
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then
				local dir = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, -1)
				humanoid:Move(dir, true)
			end
			_SetAnimState(data.InstanceId, model, "Run")
		end

	elseif data.ConfigId == "resonant_hollowed" then
		-- Resonant: Casts spheres from afar
		if dist <= config.AttackRange then
			_TryAttack(data, model, config, targetRoot, now)
			_SetAnimState(data.InstanceId, model, "Idle")
		else
			-- Keep distance / chase with Humanoid:Move
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then
				local dir = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, -1)
				humanoid:Move(dir, true)
			end
			_SetAnimState(data.InstanceId, model, "Run")
		end

	elseif data.ConfigId == "ember_hollowed" then
		-- Ember: Wide cleave sweeps
		if dist <= config.AttackRange then
			_TryAttack(data, model, config, targetRoot, now)
			_SetAnimState(data.InstanceId, model, "Idle")
		else
			-- Aggressive chase with Humanoid:Move
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then
				local dir = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, -1)
				humanoid:Move(dir, true)
			end
			_SetAnimState(data.InstanceId, model, "Run")
		end
	end
end

--[[
	Evaluate AI for a single Hollowed instance.  Called every difficulty-scaled AI tick.
]]
local function _TickAI(instanceId: string, dt: number)
	local data   = _instances[instanceId]
	local model  = _models[instanceId]
	local config = CONFIGS[data.ConfigId]
	if not data or not model or not config then return end
	if not data.IsActive or data.State == "Dead" then return end

	-- Skip attacks and movement during stagger, but allow rotation
	if data.State == "Staggered" then
		local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			data.RootPosition = rootPart.Position
		end
		return
	end

	local now          = tick()
	local rootPart     = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local rootPos = rootPart.Position
	data.RootPosition = rootPos

	-- ── Aggro detection ──────────────────────────────────────────────────────

	local nearestPlayer = _GetBestTarget(rootPos, config.AggroRange, data.FocusTargeting or 1)

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
		local target = data.Target
		local targetChar = target.Character
		local targetData = StateService:GetPlayerData(target)
		local targetRoot = targetChar and (targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
		local isValidTarget = targetChar ~= nil and targetRoot ~= nil and (not targetData or targetData.State ~= "Dead")
		local outOfRange = false
		if targetRoot then
			outOfRange = (targetRoot.Position - rootPos).Magnitude > (config.AggroRange + 5)
		end

		if (not isValidTarget) or outOfRange then
			-- Hard-drop stale/invalid targets immediately and reacquire on next AI tick.
			data.State = "Patrol"
			data.Target = nil
			data.PatrolTarget = nil
			_UpdateVisuals(instanceId)
			return
		end

		_ExecuteVariantAI(data, model, config, dt, targetRoot :: BasePart, now)

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
			_SetAnimState(instanceId, model, "Idle")
		else
			local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid then humanoid.WalkSpeed = config.MoveSpeed * 0.5 end
			_WalkTo(model, data.PatrolTarget)
			if humanoid then humanoid.WalkSpeed = config.MoveSpeed end
			_SetAnimState(instanceId, model, "Run")
		end
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	Spawn a new Hollowed instance of the given config type at spawnCF.
	Returns the instanceId, or nil if configId is unknown.
]]
function HollowedService.SpawnInstance(configId: string, spawnCF: CFrame, difficulty: number?): string?
	local config = CONFIGS[configId]
	if not config then
		warn(("[HollowedService] Unknown configId: %s"):format(configId))
		return nil
	end

	_nextId += 1
	local instanceId = ("Hollowed_%d"):format(_nextId)

	local model, _ = _CreateModel(instanceId, config, spawnCF)
	_models[instanceId] = model

	local diff = difficulty or 1

	local data: HollowedData = {
		InstanceId      = instanceId,
		ConfigId        = configId,
		SpawnCFrame     = spawnCF,
		RootPosition    = spawnCF.Position,
		CurrentHealth   = config.MaxHealth,
		MaxHealth       = config.MaxHealth,
		CurrentPoise    = config.MaxPoise,
		State           = "Patrol",
		Target          = nil,
		LastAttackTick  = 0,
		PatrolTarget    = nil,
		PatrolWaitUntil = 0,
		LastAITick      = 0,
		KillerId        = nil,
		IsActive        = true,
		Difficulty      = diff,
		FocusAggression = diff / 10,
		FocusDefense    = (10 - diff) / 15,
		FocusTargeting  = math.clamp(diff / 8, 0, 1),



	}
	_instances[instanceId] = data

	print(("[HollowedService] Spawned %s (%s) at %s"):format(instanceId, configId, tostring(spawnCF.Position)))
	return instanceId
end

function HollowedService.SetDifficulty(instanceId: string, diff: number)
	local data = _instances[instanceId]
	if data then
		data.Difficulty = diff
		data.FocusAggression = diff / 10
		data.FocusDefense = (10 - diff) / 15
		data.FocusTargeting = math.clamp(diff / 8, 0, 1)
	end
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
	_instanceAreaMap[instanceId] = nil
	_animStates[instanceId] = nil
	print(("[HollowedService] Despawned %s"):format(instanceId))
end

--[[
	Apply hit damage to a Hollowed instance (called by CombatService).
	attacker: the Player who landed the hit.
	Returns true if still alive, false if just killed.
]]
function HollowedService.ApplyDamage(instanceId: string, damage: number, attacker: Player?, postureDamage: number?): boolean
	local data   = _instances[instanceId]
	local config = data and CONFIGS[data.ConfigId]
	if not data or not config or not data.IsActive then return false end
	if data.State == "Dead" or data.State == "Dodging" then return false end

	-- Handle Blocking phase (Ironclad primarily)
	if data.State == "Blocking" then
		print(("[HollowedService] %s BLOCKED hit from %s"):format(instanceId, attacker and attacker.Name or "Unknown"))
		-- Potentially apply heavy posture damage or spark effects here
		return true
	end

	-- Apply HP damage
	data.CurrentHealth = math.max(0, data.CurrentHealth - damage)

	-- Apply Posture damage and enter stagger state with difficulty scaling
	if postureDamage then
		data.CurrentPoise = math.max(0, data.CurrentPoise - postureDamage)
		if data.CurrentPoise <= 0 then
			data.State = "Staggered"
			local diff = data.Difficulty or 1
			local diffNorm = math.clamp(diff / 10, 0, 1)
			local staggerDuration = 0.4 - 0.2 * diffNorm  -- Higher difficulty = shorter stagger
			print(("[HollowedService] %s was STAGGERED for %.2fs!"):format(instanceId, staggerDuration))
			-- Recover poise and return to Aggro
			task.delay(staggerDuration, function()
				if _instances[instanceId] and _instances[instanceId].State == "Staggered" then
					local newState = "Patrol"
					if _instances[instanceId].Target then
						newState = "Aggro"
					end
					_instances[instanceId].State = newState
					_instances[instanceId].CurrentPoise = config.MaxPoise
				end
			end)
		end
	end

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
						_PivotModel(model, offset, nil)
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

--[[
	Get all active Hollowed instances.
	Called by WitnessService to find observable Hollowed enemies.
]]
function HollowedService.GetAllInstances(): {[string]: HollowedData}
	return _instances
end

-- ─── Spawning System ──────────────────────────────────────────────────────────

--[[
	Count how many Hollowed instances are currently alive in a specific area.
]]
local function _CountInstancesInArea(areaName: string): number
	local count = 0
	for instanceId, area in _instanceAreaMap do
		if area == areaName and _instances[instanceId] and _instances[instanceId].State ~= "Dead" then
			count += 1
		end
	end
	return count
end

--[[
	Try to spawn respawns in areas that haven't hit their mob cap.
	Respects collision prevention and player distance.
]]
local function _TrySpawnRespawns()
	local variantList = {"basic_hollowed", "ironclad_hollowed", "silhouette_hollowed", "resonant_hollowed", "ember_hollowed"}

	-- Try spawning in each zone
	for _, zone in _spawnerConfig.SpawnZones do
		local currentCount = _CountInstancesInArea(zone.AreaName)
		local spotsAvailable = zone.MobCap - currentCount

		-- Spawn up to 1 mob per check cycle per zone (prevents spawn spam)
		if spotsAvailable > 0 and math.random() < 0.3 then
			-- Find a safe spawn position
			local spawnPos = SpawnerConfig.FindSafeSpawnPosition(
				zone,
				_instances,
				_spawnerConfig.CollisionCheckRadius,
				_spawnerConfig.MinSpawnDistance,
				5  -- maxAttempts
			)

			if spawnPos then
				local randomVariant = variantList[math.random(1, #variantList)]
				local spawnCF = CFrame.new(spawnPos) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
				local instanceId = HollowedService.SpawnInstance(randomVariant, spawnCF)

				-- Track which area this instance belongs to
				_instanceAreaMap[instanceId] = zone.AreaName
				print(("[HollowedService] Spawned %s in %s (%d/%d) at %s"):format(
					randomVariant, zone.AreaName, currentCount + 1, zone.MobCap, tostring(spawnPos)))
			end
		end
	end
end

--[[
	Allow SpawnerConfig override (for testing or dynamic difficulty).
]]
function HollowedService.SetSpawnerConfig(newConfig: SpawnerConfig.SpawnerConfig)
	_spawnerConfig = newConfig
	print("[HollowedService] Spawner config updated")
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

	-- Log spawner configuration
	print(("[HollowedService] Spawning system configured with %d areas"):format(#_spawnerConfig.SpawnZones))
	for _, zone in _spawnerConfig.SpawnZones do
		print(("[HollowedService]  - %s (Ring %d): MobCap=%d, Center=%s, Radius=%d"):format(
			zone.AreaName, zone.Ring, zone.MobCap, tostring(zone.CenterPosition), zone.SearchRadius))
	end

	-- AI + Spawn loop — evaluate each instance every AI_TICK_RATE seconds
	-- Also check for respawns periodically
	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		local now = tick()

		-- AI tick for existing instances with difficulty-scaled tick rates
		for instanceId, data in _instances do
			local diff = data.Difficulty or 1
			local aiTick = GetAITickForDiff(diff)
			if now - data.LastAITick >= aiTick then
				data.LastAITick = now
				local ok, err = pcall(_TickAI, instanceId, aiTick)
				if not ok then
					warn(("[HollowedService] AI tick error for %s: %s"):format(instanceId, tostring(err)))
				end
			end
		end

		-- Check for respawn opportunities periodically
		if now - _lastSpawnCheckTime >= _spawnerConfig.RespawnCheckInterval then
			_lastSpawnCheckTime = now
			_TrySpawnRespawns()
		end
	end)

	print("[HollowedService] Started — Dynamic spawning and AI loop active")
end

function HollowedService:Shutdown()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end
	for instanceId in _instances do
		HollowedService.DespawnInstance(instanceId)
		_instanceAreaMap[instanceId] = nil
	end
	print("[HollowedService] Shutdown complete")
end

return HollowedService
