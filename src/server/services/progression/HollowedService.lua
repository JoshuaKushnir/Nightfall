--!strict
--[[
	HollowedService.lua  —  Issue #143  (Phase 4 — World & Narrative)

	Server-authoritative AI for Hollowed enemies in Ring 1 (Verdant Shelf).

	─── HITBOX AXIS FIX ────────────────────────────────────────────────────────
	CFrame.LookVector = -Z in local space (Roblox convention).
	CFrame.lookAt() makes LookVector face the target.
	Therefore "in front of the mob" = root.CFrame * CFrame.new(0, 0, -N).
	All hitbox offsets use NEGATIVE Z.  Positive Z = behind.

	─── LEVEL-10 COMBAT AI ─────────────────────────────────────────────────────
	The elite AI runs a full combat micro-loop on every tick with these layers:

	  1. SPACING  — Maintains an ideal engagement distance per variant.
	               Circles / strafes to avoid standing still.

	  2. FEINT    — Before committing to an attack the mob plays a fake windup
	               (animation + brief hesitation) to bait the player's block/dodge.
	               Only the real commit spawns a hitbox.

	  3. PARRY    — While the mob is NOT in its own attack cooldown, there is a
	               small per-tick chance it enters a PARRY window.  If a player
	               hit lands during that window, damage is reflected and the
	               player is staggered instead.

	  4. BLOCK    — Separate from parry: a sustained blocking state that absorbs
	               incoming hits (posture damage only) for a short window.
	               The mob raises its block reactively when the player is close
	               and recently swung, simulating read-reaction.

	  5. DODGE    — When the mob detects an incoming player attack (via the
	               IncomingHPDamage attribute on its own dummy target, or via a
	               short reaction window after aggro), it may roll sideways out
	               of range, becoming briefly invincible.

	  6. COMBO    — After a successful hit the mob immediately checks for a
	               follow-up second strike (shorter cooldown window), chaining
	               up to 2 hits per engagement burst.

	  7. THREAT   — Reads the player's recent attack cadence (stored in
	               data.PlayerAttackCadence) to decide when to be aggressive vs
	               defensive.  If the player is spamming, the mob turtles and
	               waits for an opening.

	Dependencies: ProgressionService, PostureService, StateService,
	              NetworkProvider, RunService, CollectionService, Players
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local AnimationDatabase = require(ReplicatedStorage.Shared.AnimationDatabase)
local HitboxService     = require(ReplicatedStorage.Shared.modules.combat.HitboxService)
local DummyService      = require(script.Parent.Parent.entities.DummyService)
local StateService      = require(ReplicatedStorage.Shared.modules.core.StateService)
local NetworkProvider   = require(ReplicatedStorage.Shared.network.NetworkProvider)
local SpawnerConfig     = require(game:GetService("ServerScriptService").Server.modules.SpawnerConfig)

local ProgressionService: any = nil
local PostureService: any     = nil

local HollowedTypesModule = require(ReplicatedStorage.Shared.types.HollowedTypes)
type HollowedConfig = HollowedTypesModule.HollowedConfig
type HollowedData   = HollowedTypesModule.HollowedData
type HollowedState  = HollowedTypesModule.HollowedState
type SpawnZone      = SpawnerConfig.SpawnZone

-- ─── Service ─────────────────────────────────────────────────────────────────

local HollowedService = {}
HollowedService._initialized = false

-- ─── Timing Constants ────────────────────────────────────────────────────────

local BASE_AI_TICK        = 0.18
local PATROL_ARRIVE_DIST  = 2.0
local PATROL_WAIT_TIME    = 2.0

-- Attack phase durations (seconds)
local WINDUP              = 0.18   -- commit → hitbox
local SWING               = 0.30   -- hitbox active
local RECOVERY            = 0.50   -- post-swing lock
-- Total lock per swing   = 0.98 s  → all AttackCooldowns must be ≥ 1.0 s

-- Feint: fake windup played before the real commit to bait the player
local FEINT_DURATION      = 0.28   -- how long the fake windup looks convincing
local FEINT_COOLDOWN      = 4.0    -- minimum seconds between feints per mob

-- Parry window: mob can parry incoming hits during this window
local PARRY_WINDOW        = 0.35   -- how long the parry window stays open
local PARRY_COOLDOWN      = 5.0    -- minimum seconds between parry attempts
local PARRY_REFLECT_MULT  = 1.5    -- damage multiplier reflected back to player

-- Dodge
local DODGE_DURATION      = 0.45   -- invincibility + lateral movement time
local DODGE_DISTANCE      = 7.0    -- studs per dodge
local DODGE_COOLDOWN      = 3.0    -- minimum seconds between dodges

-- Block
local BLOCK_DURATION      = 0.8    -- max sustained block window
local BLOCK_COOLDOWN      = 2.5    -- minimum seconds between blocks

-- Combo: after a hit lands, shortened cooldown window for a follow-up
local COMBO_WINDOW        = 0.9    -- seconds after a hit during which combo applies
local COMBO_CD_MULT       = 0.45   -- multiply AttackCooldown for the follow-up swing

-- Threat: how quickly the mob reads player attack spam
local THREAT_DECAY        = 0.15   -- threat decays this much per second
local THREAT_HIT_ADD      = 1.0    -- threat added each time a player hit registers
local THREAT_TURTLE_THRESH = 2.5   -- above this → mob goes defensive

-- ─── Enemy Configs ───────────────────────────────────────────────────────────

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
		MeleeReach     = 3,    -- hitbox placed this far in front of mob
		IsRanged       = false,
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
		MeleeReach     = 4,
		IsRanged       = false,
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
		MeleeReach     = 3,
		IsRanged       = false,
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
		AttackRange    = 18,   -- preferred combat distance (stays at range)
		MeleeReach     = 18,   -- hitbox placed AT the player's position
		IsRanged       = true, -- holds distance, ranged hitbox
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
		MeleeReach     = 5,
		IsRanged       = false,
		PatrolRadius   = 25,
		MoveSpeed      = 10,
		AttackCooldown = 2.5,
		ResonanceGrant = 100,
		RespawnDelay   = 30,
		BodyColor      = BrickColor.new("Deep orange"),
	},
}

-- ─── Extended HollowedData fields (combat AI) ─────────────────────────────────
--[[
	These fields are appended to each instance table at spawn time.
	They are not in HollowedTypes to avoid type file churn during iteration.

	.LastFeintTick      : number   — tick() of last feint attempt
	.LastParryTick      : number   — tick() of last parry window open
	.LastDodgeTick      : number   — tick() of last dodge
	.LastBlockTick      : number   — tick() of last block attempt
	.LastHitLandedTick  : number   — tick() when this mob last landed a hit on player
	.ComboAvailable     : boolean  — true during COMBO_WINDOW after a hit
	.InParryWindow      : boolean  — true while parry is active
	.PlayerThreat       : number   — accumulated aggression score from player attacks
	.StrafeDir          : number   — +1 or -1, flipped periodically for circle-strafe
	.StrafeFlipTick     : number   — tick() of last strafe direction flip
	.IdealRange         : number   — per-variant preferred engagement distance
]]

-- ─── State ───────────────────────────────────────────────────────────────────

local _instances: {[string]: HollowedData}    = {}
local _models:    {[string]: Model}           = {}
local _animStates:{[string]: string}          = {}
local _intentMap: {[string]: string}          = {}
local _nextId = 0
local _heartbeatConn: RBXScriptConnection?    = nil
local _spawnerConfig: SpawnerConfig.SpawnerConfig = SpawnerConfig.GetDefaultConfig()
local _lastSpawnCheckTime: number = 0
local _instanceAreaMap: {[string]: string}    = {}

-- Extended per-instance combat state (avoids casting HollowedData everywhere)
type ExtData = {
	LastFeintTick     : number,
	LastParryTick     : number,
	LastDodgeTick     : number,
	LastBlockTick     : number,
	LastHitLandedTick : number,
	LastAggroTick     : number,
	ComboAvailable    : boolean,
	InParryWindow     : boolean,
	PlayerThreat      : number,
	StrafeDir         : number,
	StrafeFlipTick    : number,
	IdealRange        : number,
	FocusTargeting    : number,
}
local _ext: {[string]: ExtData} = {}

-- ─── Private — Rig & Model ────────────────────────────────────────────────────

local function _RigModel(model: Model)
	local root  = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	if not root or not torso then return end

	local function joint(name, p0, p1, c0, c1)
		local m = Instance.new("Motor6D")
		m.Name = name; m.Part0 = p0; m.Part1 = p1; m.C0 = c0; m.C1 = c1
		m.Parent = p0
	end

	joint("RootJoint", root, torso,
		CFrame.new(0,0,0,-1,0,0,0,0,1,0,1,-0), CFrame.new(0,0,0,-1,0,0,0,0,1,0,1,-0))

	local head = model:FindFirstChild("Head")
	if head then
		joint("Neck", torso, head,
			CFrame.new(0,1,0,-1,0,0,0,0,1,0,1,-0), CFrame.new(0,-0.5,0,-1,0,0,0,0,1,0,1,-0))
	end
	local lA = model:FindFirstChild("Left Arm")
	if lA then
		joint("Left Shoulder", torso, lA,
			CFrame.new(-1,0.5,0,-0,-0,-1,0,1,0,1,0,0), CFrame.new(0.5,0.5,0,-0,-0,-1,0,1,0,1,0,0))
	end
	local rA = model:FindFirstChild("Right Arm")
	if rA then
		joint("Right Shoulder", torso, rA,
			CFrame.new(1,0.5,0,0,0,1,0,1,-0,-1,0,0), CFrame.new(-0.5,0.5,0,0,0,1,0,1,-0,-1,0,0))
	end
	local lL = model:FindFirstChild("Left Leg")
	if lL then
		joint("Left Hip", torso, lL,
			CFrame.new(-1,-1,0,-0,-0,-1,0,1,0,1,0,0), CFrame.new(0.5,1,0,-0,-0,-1,0,1,0,1,0,0))
	end
	local rL = model:FindFirstChild("Right Leg")
	if rL then
		joint("Right Hip", torso, rL,
			CFrame.new(1,-1,0,0,0,1,0,1,-0,-1,0,0), CFrame.new(-0.5,1,0,0,0,1,0,1,-0,-1,0,0))
	end
end

local function _CreateModel(instanceId: string, config: HollowedConfig, spawnCF: CFrame): (Model, BasePart)
	local model  = Instance.new("Model")
	model.Name   = instanceId
	local origin = spawnCF.Position + Vector3.new(0, 3, 0)
	local color  = config.BodyColor

	local function makePart(name: string, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name; p.Size = size
		p.CFrame = CFrame.new(origin + offset)
		p.Anchored   = false  -- physics-driven; Humanoid:MoveTo handles movement
		p.CanCollide = false  -- no collision so parts don't push player or each other
		p.BrickColor = color
		p.Material = Enum.Material.SmoothPlastic
		if name == "HumanoidRootPart" then p.Transparency = 1 end
		p.Parent = model
		return p
	end

	local root = makePart("HumanoidRootPart", Vector3.new(2,2,1), Vector3.new(0,0,0))
	makePart("Torso",     Vector3.new(2,2,1), Vector3.new(0,   1.5,  0))
	makePart("Head",      Vector3.new(1,1,1), Vector3.new(0,   3,    0))
	makePart("Left Arm",  Vector3.new(1,2,1), Vector3.new(-1.5,1.5,  0))
	makePart("Right Arm", Vector3.new(1,2,1), Vector3.new( 1.5,1.5,  0))
	makePart("Left Leg",  Vector3.new(1,2,1), Vector3.new(-0.5,-0.5, 0))
	makePart("Right Leg", Vector3.new(1,2,1), Vector3.new( 0.5,-0.5, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = config.MaxHealth; humanoid.Health = config.MaxHealth
	humanoid.WalkSpeed = config.MoveSpeed
	humanoid.AutoRotate     = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	_RigModel(model)

	local animator = Instance.new("Animator", humanoid)
	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = AnimationDatabase.Movement.Idle
	local idleTrack = animator:LoadAnimation(idleAnim)
	idleTrack.Looped = true; idleTrack:Play()

	local head2: BasePart? = model:FindFirstChild("Head") :: BasePart?
	if head2 then
		local bb = Instance.new("BillboardGui")
		bb.Name = "HollowedHUD"; bb.Adornee = head2
		bb.Size = UDim2.new(0,120,0,40); bb.StudsOffset = Vector3.new(0,2.5,0)
		bb.AlwaysOnTop = false; bb.Parent = model

		local nl = Instance.new("TextLabel")
		nl.Name = "NameLabel"; nl.Size = UDim2.new(1,0,0.5,0)
		nl.BackgroundTransparency = 1; nl.TextColor3 = Color3.fromRGB(220,80,80)
		nl.TextScaled = true; nl.Font = Enum.Font.GothamBold
		nl.Text = config.DisplayName; nl.Parent = bb

		local hb2 = Instance.new("Frame")
		hb2.Name = "HealthBar"; hb2.BackgroundColor3 = Color3.fromRGB(210,45,45)
		hb2.BorderSizePixel = 0; hb2.Size = UDim2.new(1,0,0.3,0)
		hb2.Position = UDim2.new(0,0,0.65,0); hb2.Parent = bb
	end

	model.PrimaryPart = root :: PVInstance
	model.Parent = Workspace
	return model, root :: BasePart
end

local function _UpdateVisuals(instanceId: string)
	local data  = _instances[instanceId]
	local model = _models[instanceId]
	if not data or not model then return end
	local ex    = _ext[instanceId]
	local hpFrac = math.clamp(data.CurrentHealth / data.MaxHealth, 0, 1)
	local col =
		if data.State == "Dead"     then BrickColor.new("Medium stone grey")
		elseif data.State == "Attacking" or data.State == "Aggro"
		                            then BrickColor.new("Bright red")
		elseif data.State == "Blocking" or ex.InParryWindow
		                            then BrickColor.new("Bright blue")
		elseif data.State == "Dodging"  then BrickColor.new("Bright yellow")
		else                             BrickColor.new("Dark stone grey")

	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			(p :: BasePart).BrickColor = col
		end
	end
	local bb  = model:FindFirstChild("HollowedHUD", true)
	local bar = bb and bb:FindFirstChild("HealthBar")
	if bar and bar:IsA("Frame") then
		(bar :: Frame).Size = UDim2.new(hpFrac, 0, 0.3, 0)
	end
end

-- ─── Movement helpers ────────────────────────────────────────────────────────
--[[
	All parts are Anchored = true.  Humanoid:MoveTo has zero effect on anchored
	parts — it only works on physics-simulated rigs.  Movement is driven manually
	by calling _MoveModel / _StrafeModel every AI tick, which shift the entire
	model via PivotTo.

	_StopMovement and _RestoreSpeed are kept as no-ops so call sites in the
	attack/dodge/block code compile without changes.
]]

local function _GetHumanoid(model: Model): Humanoid?
	return model:FindFirstChild("Humanoid") :: Humanoid?
end

local function _GetRoot(model: Model): BasePart?
	return (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

--[[
	Step the model toward targetPos by (speed × dt) studs, staying on the XZ
	plane of the root.  Automatically faces the direction of travel.
	Returns the distance remaining after the step.
]]
local function _MoveModel(model: Model, targetPos: Vector3, speed: number, _dt: number): number
	local h = _GetHumanoid(model)
	local root = _GetRoot(model)
	if not h or not root then return 0 end
	h.WalkSpeed = speed
	local flat = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
	local dist = (flat - root.Position).Magnitude
	if dist < 0.5 then
		h.WalkSpeed = 0
		return 0
	end
	h:MoveTo(targetPos)
	return dist
end

--[[
	Step the model sideways relative to the direction toward facePos.
	sign: +1 = right, -1 = left.  Model keeps facing facePos while moving.
]]
local function _StrafeModel(model: Model, facePos: Vector3, sign: number, speed: number, _dt: number)
	local h = _GetHumanoid(model)
	local root = _GetRoot(model)
	if not h or not root then return end
	h.WalkSpeed = speed
	local toTarget = Vector3.new(facePos.X - root.Position.X, 0, facePos.Z - root.Position.Z)
	if toTarget.Magnitude < 0.01 then return end
	local sideDir = if sign >= 0
		then toTarget.Unit:Cross(Vector3.yAxis)
		else Vector3.yAxis:Cross(toTarget.Unit)
	local sideTarget = root.Position + sideDir.Unit * 4
	h:MoveTo(sideTarget)
end

--[[
	Face the model toward facePos (used when attacking while stationary).
]]
local function _FaceTarget(model: Model, facePos: Vector3)
	local root = _GetRoot(model)
	if not root then return end
	local dir = Vector3.new(facePos.X - root.Position.X, 0, facePos.Z - root.Position.Z)
	if dir.Magnitude < 0.01 then return end
	local targetCF = CFrame.lookAt(root.Position, root.Position + dir)
	root.CFrame = root.CFrame:Lerp(targetCF, 0.3)
end

local function _StopMovement(model: Model)
	local h = _GetHumanoid(model)
	if h then h.WalkSpeed = 0 end
end
local function _RestoreSpeed(model: Model, speed: number)
	local h = _GetHumanoid(model)
	if h then h.WalkSpeed = speed end
end

-- ─── Animation helpers ────────────────────────────────────────────────────────

local function _GetAnimator(model: Model): Animator?
	local h = _GetHumanoid(model)
	if not h then return nil end
	return h:FindFirstChild("Animator") :: Animator?
		or Instance.new("Animator", h)
end

local function _SetLoopAnim(instanceId: string, model: Model, state: "Idle" | "Run")
	if _animStates[instanceId] == state then return end
	_animStates[instanceId] = state
	local anim = _GetAnimator(model)
	if not anim then return end
	for _, t in anim:GetPlayingAnimationTracks() do
		if t.Animation.AnimationId == AnimationDatabase.Movement.Idle
		or t.Animation.AnimationId == AnimationDatabase.Movement.Run then
			t:Stop(0.2)
		end
	end
	local a = Instance.new("Animation")
	a.AnimationId = (state == "Run") and AnimationDatabase.Movement.Run or AnimationDatabase.Movement.Idle
	local tr = anim:LoadAnimation(a); tr.Looped = true; tr:Play(0.2)
end

local function _PlayOneshot(model: Model, animId: string)
	if animId == "" or animId == "rbxassetid://0" then return end
	local anim = _GetAnimator(model)
	if not anim then return end
	local a = Instance.new("Animation"); a.AnimationId = animId
	local tr = anim:LoadAnimation(a); tr:Play()
end

local function _PickAttackAnim(configId: string): string
	if configId == "silhouette_hollowed" then
		return AnimationDatabase.Combat.Aspect.Ash.AshenStep
	elseif configId == "resonant_hollowed" then
		return AnimationDatabase.Combat.Aspect.Gale.WindStrike
	elseif configId == "ember_hollowed" then
		return AnimationDatabase.Combat.Aspect.Ember.Surge
	end
	local pool = {
		AnimationDatabase.Combat.General.Punch1,
		AnimationDatabase.Combat.General.Punch2,
		AnimationDatabase.Combat.General.Punch3,
		AnimationDatabase.Combat.General.LeftHit,
		AnimationDatabase.Combat.General.RightHit,
	}
	return pool[math.random(1, #pool)]
end

-- ─── Target utils ─────────────────────────────────────────────────────────────

local function _GetBestTarget(origin: Vector3, maxRange: number, focusTgt: number): Player?
	local best: Player? = nil
	local bestScore = -math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local pd = StateService:GetPlayerData(player)
		if pd and pd.State == "Dead" then continue end
		local r = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not r then continue end
		local dist = (r.Position - origin).Magnitude
		if dist <= maxRange then
			local score = -dist
			if pd then score += (1 - math.clamp((pd.CurrentHealth or 100)/(pd.MaxHealth or 100), 0, 1)) * 30 * focusTgt end
			if score > bestScore then bestScore = score; best = player end
		end
	end
	return best
end

local function _GetPlayerRoot(player: Player): BasePart?
	local char = player.Character
	return char and (char:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
end

-- ─── Core attack executor ────────────────────────────────────────────────────

--[[
	Spawn a hitbox in front of the mob.

	AXIS NOTE:  CFrame.LookVector = -Z in Roblox.
	            root.CFrame * CFrame.new(0, 0, -3)  →  3 studs FORWARD.
	            Negative Z offset = in front.  Do NOT use positive Z.

	@param targetRootSnap  The player's root at the moment of commit.  Used for:
	                       - face-lock before windup fires
	                       - range re-check inside the delay (FIX D)
	@param isCombo         If true, skip the feint check and use a shorter recovery
]]
local function _FireHitbox(
	data          : HollowedData,
	model         : Model,
	config        : HollowedConfig,
	targetSnap    : BasePart,
	isCombo       : boolean?
)
	data.State          = "Attacking"
	data.LastAttackTick = tick()
	_intentMap[data.InstanceId] = ""
	_UpdateVisuals(data.InstanceId)
	_SetLoopAnim(data.InstanceId, model, "Idle")
	_StopMovement(model)
	_FaceTarget(model, targetSnap.Position)
	_PlayOneshot(model, _PickAttackAnim(data.ConfigId))

	local root = _GetRoot(model)
	if not root then
		_RestoreSpeed(model, config.MoveSpeed)
		if _instances[data.InstanceId] then _instances[data.InstanceId].State = "Aggro" end
		return
	end

	task.delay(WINDUP, function()
		local live = _instances[data.InstanceId]
		if not live or live.State ~= "Attacking" then
			_RestoreSpeed(model, config.MoveSpeed)
			return
		end

		-- Range re-check: cancel if player escaped during windup
		local rootNow    = _GetRoot(model)
		local liveRoot   = _GetPlayerRoot(live.Target)
		local checkPos   = liveRoot and liveRoot.Position or targetSnap.Position
		if rootNow then
			local distNow = (checkPos - rootNow.Position).Magnitude
			if distNow > config.AttackRange * 1.6 then
				task.delay(RECOVERY, function()
					local l2 = _instances[data.InstanceId]
					if l2 and l2.State == "Attacking" then
						l2.State = "Aggro"
						_RestoreSpeed(model, config.MoveSpeed)
						_UpdateVisuals(data.InstanceId)
					end
				end)
				return
			end
		end

		-- Re-face at impact using live player position
		local liveTarget = _GetPlayerRoot(live.Target)
		local aimPos     = liveTarget and liveTarget.Position or targetSnap.Position
		_FaceTarget(model, aimPos)

		local root2 = _GetRoot(model)
		if not root2 then return end

		-- For ranged mobs: place hitbox AT the player.
		-- For melee mobs: place hitbox MeleeReach studs in front of the mob.
		local reach  = (config :: any).MeleeReach or 3
		local isRanged = (config :: any).IsRanged or false
		local hitPos: Vector3
		if isRanged then
			-- Ranged: place a sphere hitbox at the player's position
			hitPos = aimPos
		else
			-- Melee: place hitbox forward of the mob root
			hitPos = (root2.CFrame * CFrame.new(0, 0, -reach)).Position
		end
		local hitCF = CFrame.new(hitPos)

		local hb = HitboxService.CreateHitbox({
			Shape         = "Box",
			Owner         = data.InstanceId,
			Damage        = config.AttackDamage,
			PostureDamage = config.PostureDamage,
			Position      = hitCF.Position,
			CFrame        = hitCF,
			Size          = Vector3.new(4, 4, 4),
			Radius        = 4,
			Duration      = SWING,
		})

		local origOnHit = hb.Config.OnHit
		hb.Config.OnHit = function(target: any, hitData: any)
			if origOnHit then pcall(origOnHit, target, hitData) end

			local dmg  = hb.Config.Damage        or config.AttackDamage  or 0
			local post = hb.Config.PostureDamage  or config.PostureDamage or 0

			if typeof(target) == "Instance" and target:IsA("Player") then
				local ply  = target :: Player
				local char = ply.Character
				if char and char.Parent then
					local pd = StateService:GetPlayerData(ply)
					-- Record threat: player just got hit, opening for combo
					local extD = _ext[data.InstanceId]
					if extD then
						extD.LastHitLandedTick = tick()
						extD.ComboAvailable    = true
					end
					if pd and pd.State == "Blocking" then
						local ep = (char:GetAttribute("IncomingPostureDamage") or 0) :: number
						char:SetAttribute("IncomingPostureDamage", ep + post)
						char:SetAttribute("IncomingPostureDamageSource", data.InstanceId .. "_Attack")
					else
						local eh = (char:GetAttribute("IncomingHPDamage") or 0) :: number
						char:SetAttribute("IncomingHPDamage", eh + dmg)
						char:SetAttribute("IncomingHPDamageSource", data.InstanceId .. "_Attack")
					end
				end
			elseif type(target) == "string" and DummyService and DummyService.ApplyDamage then
				pcall(DummyService.ApplyDamage, target, dmg)
			end
		end

		HitboxService.TestHitbox(hb)

		local recoverTime = isCombo and (RECOVERY * 0.6) or RECOVERY
		task.delay(SWING + recoverTime, function()
			local l2 = _instances[data.InstanceId]
			if l2 and l2.State == "Attacking" then
				l2.State = "Aggro"
				_RestoreSpeed(model, config.MoveSpeed)
				_UpdateVisuals(data.InstanceId)
			end
		end)
	end)
end

-- ─── Combat behaviour primitives ─────────────────────────────────────────────

--[[
	Try to commit a real attack.  Returns true if attack was fired.
	Checks cooldown, range, aggro grace period.
	If difficulty ≥ 8, considers threat level and may delay to turtle.
]]
local function _TryAttack(
	data       : HollowedData,
	model      : Model,
	config     : HollowedConfig,
	targetRoot : BasePart,
	now        : number,
	isCombo    : boolean?
): boolean
	local root = _GetRoot(model)
	if not root then return false end
	local ex   = _ext[data.InstanceId]
	if not ex  then return false end
	local dist = (targetRoot.Position - root.Position).Magnitude
	if dist > config.AttackRange then return false end

	-- Aggro grace period
	if now - (ex.LastAggroTick or now) < 0.3 then return false end

	-- Difficulty-scaled cooldown
	local diff     = math.clamp(data.Difficulty or 5, 1, 10)
	local diffNorm = (diff - 5) / 5                          -- -1..+1
	local cdMult   = isCombo and COMBO_CD_MULT or (1.0 - 0.3 * diffNorm)
	if now - data.LastAttackTick < config.AttackCooldown * cdMult then return false end

	-- High-difficulty threat check: if player is hammering, wait for opening
	local threat = ex.PlayerThreat or 0
	if diff >= 8 and threat > THREAT_TURTLE_THRESH and not isCombo then
		return false
	end

	_FireHitbox(data, model, config, targetRoot, isCombo)
	return true
end

--[[
	Perform a feint: play the attack animation start WITHOUT spawning a hitbox.
	Stalls movement briefly to sell the fake.
	Returns true if feint was performed.
]]
local function _TryFeint(
	data       : HollowedData,
	model      : Model,
	config     : HollowedConfig,
	targetRoot : BasePart,
	now        : number
): boolean
	local ex = _ext[data.InstanceId]
	if not ex then return false end
	local diff = math.clamp(data.Difficulty or 1, 1, 10)
	if diff < 7 then return false end  -- feints only at difficulty 7+

	local lastFeint = ex.LastFeintTick or 0
	if now - lastFeint < FEINT_COOLDOWN then return false end

	local root = _GetRoot(model)
	if not root then return false end
	local dist = (targetRoot.Position - root.Position).Magnitude
	-- Only feint when close enough to be convincing
	if dist > config.AttackRange * 2 then return false end

	-- Roll: 25% chance per tick when eligible
	if math.random() > 0.25 then return false end

	ex.LastFeintTick = now
	_FaceTarget(model, targetRoot.Position)
	_StopMovement(model)
	-- Play the attack anim start (no hitbox)
	_PlayOneshot(model, _PickAttackAnim(data.ConfigId))

	-- After the feint duration, resume normal AI
	task.delay(FEINT_DURATION, function()
		local live = _instances[data.InstanceId]
		if live and live.State == "Aggro" then
			_RestoreSpeed(model, config.MoveSpeed)
		end
	end)

	return true
end

--[[
	Open a parry window.  While InParryWindow is true, incoming hits are
	reflected in ApplyDamage.  Returns true if parry window was opened.
]]
local function _TryParry(
	data  : HollowedData,
	model : Model,
	config: HollowedConfig,
	now   : number
): boolean
	local ex = _ext[data.InstanceId]
	if not ex then return false end
	local diff = math.clamp(data.Difficulty or 1, 1, 10)
	if diff < 8 then return false end  -- parry only at difficulty 8+

	local lastParry = ex.LastParryTick or 0
	if now - lastParry < PARRY_COOLDOWN then return false end
	if ex.InParryWindow then return false end
	if now - data.LastAttackTick < config.AttackCooldown * 0.5 then return false end

	-- Roll: chance scales with difficulty above 8
	local chance = 0.04 + 0.03 * (diff - 8)   -- 4% at diff 8, 10% at diff 10
	if math.random() > chance then return false end

	ex.LastParryTick  = now
	ex.InParryWindow  = true
	_StopMovement(model)
	_UpdateVisuals(data.InstanceId)

	task.delay(PARRY_WINDOW, function()
		local live = _instances[data.InstanceId]
		if live then
			local ex = _ext[data.InstanceId]
			if ex then ex.InParryWindow = false end
			_RestoreSpeed(model, config.MoveSpeed)
			_UpdateVisuals(data.InstanceId)
		end
	end)

	return true
end

--[[
	Enter a blocking state reactively (player recently attacked, mob is nearby).
	Returns true if block was raised.
]]
local function _TryBlock(
	data       : HollowedData,
	model      : Model,
	config     : HollowedConfig,
	targetRoot : BasePart,
	now        : number
): boolean
	local ex = _ext[data.InstanceId]
	if not ex then return false end
	local diff = math.clamp(data.Difficulty or 1, 1, 10)
	if diff < 6 then return false end  -- block at difficulty 6+

	local lastBlock = ex.LastBlockTick or 0
	if now - lastBlock < BLOCK_COOLDOWN then return false end
	if data.State == "Blocking" then return false end

	local root = _GetRoot(model)
	if not root then return false end
	local dist = (targetRoot.Position - root.Position).Magnitude
	-- Only worth blocking when the player can actually reach us
	if dist > config.AttackRange * 1.5 then return false end

	-- Block chance scales with threat: mob blocks MORE when being hammered
	local threat = ex.PlayerThreat or 0
	local chance = 0.04 + 0.05 * math.clamp(threat / THREAT_TURTLE_THRESH, 0, 1) * (diff / 10)
	if math.random() > chance then return false end

	ex.LastBlockTick = now
	data.State = "Blocking"
	_StopMovement(model)
	_FaceTarget(model, targetRoot.Position)
	_UpdateVisuals(data.InstanceId)

	task.delay(BLOCK_DURATION, function()
		local live = _instances[data.InstanceId]
		if live and live.State == "Blocking" then
			live.State = "Aggro"
			_RestoreSpeed(model, config.MoveSpeed)
			_UpdateVisuals(data.InstanceId)
		end
	end)

	return true
end

--[[
	Perform a lateral dodge away from the incoming threat.
	Mob becomes invincible (Dodging state) for DODGE_DURATION.
]]
local function _TryDodge(
	data       : HollowedData,
	model      : Model,
	config     : HollowedConfig,
	targetRoot : BasePart,
	now        : number
): boolean
	local ex = _ext[data.InstanceId]
	if not ex then return false end
	local diff = math.clamp(data.Difficulty or 1, 1, 10)
	if diff < 7 then return false end  -- dodge at difficulty 7+

	local lastDodge = ex.LastDodgeTick or 0
	if now - lastDodge < DODGE_COOLDOWN then return false end
	if data.State == "Dodging" then return false end

	local root = _GetRoot(model)
	if not root then return false end
	local dist = (targetRoot.Position - root.Position).Magnitude

	-- Dodge chance spikes when the player is very close (about to swing)
	local threat = ex.PlayerThreat or 0
	local proximityFactor = math.clamp(1 - (dist / (config.AttackRange * 1.2)), 0, 1)
	local chance = proximityFactor * 0.12 * (diff / 10) * math.clamp(threat / 1.5, 0, 2)
	if math.random() > chance then return false end

	ex.LastDodgeTick = now
	data.State = "Dodging"
	_StopMovement(model)
	_UpdateVisuals(data.InstanceId)

	-- Pick a lateral direction (perpendicular to player)
	local toTarget = (targetRoot.Position - root.Position)
	local flat     = Vector3.new(toTarget.X, 0, toTarget.Z)
	local sideDir  = if ex.StrafeDir == 1
		then flat.Unit:Cross(Vector3.yAxis)
		else Vector3.yAxis:Cross(flat.Unit)

	-- Slide the mob laterally — instant dash via PivotTo
	local dodgeTarget = root.Position + sideDir.Unit * DODGE_DISTANCE
	model:PivotTo(CFrame.lookAt(dodgeTarget, dodgeTarget + flat.Unit))

	task.delay(DODGE_DURATION, function()
		local live = _instances[data.InstanceId]
		if live and live.State == "Dodging" then
			live.State = "Aggro"
			_RestoreSpeed(model, config.MoveSpeed)
			_UpdateVisuals(data.InstanceId)
		end
	end)

	return true
end

-- ─── Patrol ───────────────────────────────────────────────────────────────────

local function _RandomPatrolPoint(spawnPos: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local d     = math.random() * radius
	return Vector3.new(spawnPos.X + math.cos(angle)*d, spawnPos.Y, spawnPos.Z + math.sin(angle)*d)
end

-- ─── AI tick ─────────────────────────────────────────────────────────────────

local function GetAITickForDiff(diff: number): number
	return BASE_AI_TICK - 0.06 * (diff / 10)
end

local function _TickAI(instanceId: string, dt: number)
	local data   = _instances[instanceId]
	local model  = _models[instanceId]
	if not data or not model then return end
	local config = CONFIGS[data.ConfigId]
	if not config then return end
	if not data.IsActive or data.State == "Dead" then return end

	local ex = _ext[instanceId]
	if not ex then return end

	local now      = tick()
	local rootPart = _GetRoot(model)
	if not rootPart then return end
	data.RootPosition = rootPart.Position
	local rootPos  = rootPart.Position

	-- Skip AI during hard-locked states
	if data.State == "Attacking" or data.State == "Stunned" or data.State == "Staggered"
	or data.State == "Dodging" then return end

	-- ── Decay player threat score ────────────────────────────────────────────
	local threat = ex.PlayerThreat or 0
	threat = math.max(0, threat - THREAT_DECAY * dt)
	ex.PlayerThreat = threat

	-- ── Strafe direction: flip every 2–4 seconds ──────────────────────────────
	local strafeFlip = ex.StrafeFlipTick or 0
	if now - strafeFlip > 2 + math.random() * 2 then
		ex.StrafeDir      = math.random() < 0.5 and 1 or -1
		ex.StrafeFlipTick = now
	end

	-- ── Aggro detection ──────────────────────────────────────────────────────
	local nearest = _GetBestTarget(rootPos, config.AggroRange, ex.FocusTargeting or 1)
	if nearest and data.State ~= "Attacking" then
		if data.State ~= "Aggro" then
			data.State = "Aggro"
			data.Target = nearest
			ex.LastAggroTick = now
			_UpdateVisuals(instanceId)
		end
		data.Target = nearest
	elseif not nearest and data.State == "Aggro" then
		data.State = "Patrol"
		data.Target = nil; data.PatrolTarget = nil
		_UpdateVisuals(instanceId)
	end

	-- ── Aggro state ──────────────────────────────────────────────────────────
	if data.State == "Aggro" and data.Target then
		local target     = data.Target
		local targetRoot = _GetPlayerRoot(target)
		local pd         = StateService:GetPlayerData(target)
		local alive      = targetRoot ~= nil and (not pd or pd.State ~= "Dead")
		local inRange    = targetRoot and (targetRoot.Position - rootPos).Magnitude <= config.AggroRange + 5

		if not alive or not inRange then
			data.State = "Patrol"; data.Target = nil; data.PatrolTarget = nil
			_UpdateVisuals(instanceId); return
		end

		local tr     = targetRoot :: BasePart
		local dist   = (tr.Position - rootPos).Magnitude
		local diff2  = math.clamp(data.Difficulty or 1, 1, 10)

		-- ── Combo follow-up check (highest priority after state checks) ───────
		local comboAvail = ex.ComboAvailable
		local lastHit    = ex.LastHitLandedTick or 0
		if comboAvail and (now - lastHit) < COMBO_WINDOW then
			if _TryAttack(data, model, config, tr, now, true) then
				ex.ComboAvailable = false
				return
			end
		else
			ex.ComboAvailable = false
		end

		-- ── Parry window attempt ───────────────────────────────────────────────
		if _TryParry(data, model, config, now) then return end

		-- ── Block attempt ──────────────────────────────────────────────────────
		if data.State == "Blocking" then
			-- Already blocking — just face the threat
			_FaceTarget(model, tr.Position)
			return
		end
		if _TryBlock(data, model, config, tr, now) then return end

		-- ── Dodge attempt ─────────────────────────────────────────────────────
		if _TryDodge(data, model, config, tr, now) then return end

		-- ── Feint attempt ─────────────────────────────────────────────────────
		if _TryFeint(data, model, config, tr, now) then return end

		-- ── Spacing + attack ──────────────────────────────────────────────────
		--
		-- Movement is driven by _MoveModel (PivotTo each tick) — Humanoid:MoveTo
		-- has no effect on anchored parts.
		--
		-- Melee mobs close to AttackRange then attack.
		-- Ranged mobs hold at AttackRange ± 20%, strafe, and fire from distance.

		local isRanged   = (config :: any).IsRanged or false
		local closeRange = config.AttackRange * 1.5
		local holdMin    = config.AttackRange * 0.75  -- ranged: don't let player get closer
		local strafeDir  = ex.StrafeDir or 1
		local turtling   = diff2 >= 8 and threat > THREAT_TURTLE_THRESH

		local lastIntent = _intentMap[instanceId] or ""
		local function intent(key: string, anim: "Idle" | "Run")
			if lastIntent ~= key then
				_SetLoopAnim(instanceId, model, anim)
				_intentMap[instanceId] = key
			end
		end

		-- Predict where the player will be a short time from now
		local vel       = tr.AssemblyLinearVelocity
		local diffN     = math.clamp(diff2 / 10, 0, 1)
		local lead      = 0.1 + 0.2 * diffN
		local predicted = Vector3.new(
			tr.Position.X + vel.X * lead,
			tr.Position.Y,
			tr.Position.Z + vel.Z * lead
		)

		if isRanged then
			-- ── Ranged behaviour ──────────────────────────────────────────────
			-- Hold at AttackRange. If player gets too close, back up.
			-- Always strafe. Fire when in range.
			if dist < holdMin then
				-- Player too close — back away
				intent("backoff", "Run")
				local awayDir = Vector3.new(rootPos.X - tr.Position.X, 0, rootPos.Z - tr.Position.Z)
				if awayDir.Magnitude > 0.01 then
					_MoveModel(model, rootPos + awayDir.Unit * 10, config.MoveSpeed, dt)
				end
			elseif dist > closeRange then
				-- Too far — close until in range
				intent("chase", "Run")
				_MoveModel(model, predicted, config.MoveSpeed, dt)
			else
				-- In ideal range — strafe and attack
				intent("strafe", "Run")
				_StrafeModel(model, tr.Position, strafeDir, config.MoveSpeed, dt)
				_TryAttack(data, model, config, tr, now, false)
			end
			-- Always face target
			_FaceTarget(model, tr.Position)

		elseif dist <= config.AttackRange then
			-- ── Melee: in attack range ────────────────────────────────────────
			if turtling then
				intent("backoff", "Run")
				local awayDir = Vector3.new(rootPos.X - tr.Position.X, 0, rootPos.Z - tr.Position.Z)
				if awayDir.Magnitude > 0.01 then
					_MoveModel(model, rootPos + awayDir.Unit * 8, config.MoveSpeed, dt)
				end
			elseif _TryAttack(data, model, config, tr, now, false) then
				intent("attack", "Idle")
			else
				-- On cooldown — circle-strafe to stay unpredictable
				intent("circle", "Run")
				_StrafeModel(model, tr.Position, strafeDir, config.MoveSpeed, dt)
			end

		elseif dist > closeRange then
			-- ── Melee: far — run straight at player ───────────────────────────
			intent("chase", "Run")
			_MoveModel(model, predicted, config.MoveSpeed, dt)

		else
			-- ── Melee: closing zone — advance until in attack range ───────────
			intent("advance", "Run")
			_MoveModel(model, tr.Position, config.MoveSpeed, dt)
		end

		-- Face target when standing still (attack intent)
		if _intentMap[instanceId] == "attack" then
			_FaceTarget(model, tr.Position)
		end

	-- ── Patrol state ─────────────────────────────────────────────────────────
	elseif data.State == "Patrol" then
		if now < data.PatrolWaitUntil then return end
		if not data.PatrolTarget then
			data.PatrolTarget = _RandomPatrolPoint(data.SpawnCFrame.Position, config.PatrolRadius)
		end
		local toWP = data.PatrolTarget - rootPos
		if toWP.Magnitude <= PATROL_ARRIVE_DIST then
			data.PatrolTarget    = nil
			data.PatrolWaitUntil = now + PATROL_WAIT_TIME
			_SetLoopAnim(instanceId, model, "Idle")
		else
			_MoveModel(model, data.PatrolTarget, config.MoveSpeed * 0.5, dt)
			_SetLoopAnim(instanceId, model, "Run")
		end
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function HollowedService.SpawnInstance(configId: string, spawnCF: CFrame, difficulty: number?): string?
	local config = CONFIGS[configId]
	if not config then
		warn(("[HollowedService] Unknown configId: %s"):format(configId))
		return nil
	end
	_nextId += 1
	local instanceId = ("Hollowed_%d"):format(_nextId)
	local model, _   = _CreateModel(instanceId, config, spawnCF)
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
		LastAggroTick   = 0,
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
	-- Extra combat fields (initialised as a single table to avoid nil-index errors)
	_ext[instanceId] = {
		LastFeintTick     = 0,
		LastParryTick     = 0,
		LastDodgeTick     = 0,
		LastBlockTick     = 0,
		LastHitLandedTick = 0,
		LastAggroTick     = 0,
		ComboAvailable    = false,
		InParryWindow     = false,
		PlayerThreat      = 0,
		StrafeDir         = math.random() < 0.5 and 1 or -1,
		StrafeFlipTick    = 0,
		IdealRange        = config.AttackRange * 0.85,
		FocusTargeting    = math.clamp(diff / 8, 0, 1),
	}

	_instances[instanceId] = data
	print(("[HollowedService] Spawned %s (%s) diff=%d"):format(instanceId, configId, diff))
	return instanceId
end

function HollowedService.DespawnInstance(instanceId: string)
	local m = _models[instanceId]
	if m then m:Destroy(); _models[instanceId] = nil :: any end
	_instances[instanceId]       = nil :: any
	_instanceAreaMap[instanceId] = nil
	_animStates[instanceId]      = nil
	_intentMap[instanceId]       = nil
	_ext[instanceId]             = nil :: any
end

--[[
	Apply damage from a player hit.
	If the mob is in a PARRY window the damage is reflected to the player instead.
	If the mob is BLOCKING, only posture damage applies.
]]
function HollowedService.ApplyDamage(instanceId: string, damage: number, attacker: Player?, postureDamage: number?): boolean
	local data   = _instances[instanceId]
	local config = data and CONFIGS[data.ConfigId]
	if not data or not config or not data.IsActive then return false end
	if data.State == "Dead" or data.State == "Dodging" then return false end  -- Dodging = invincible

	local ex = _ext[instanceId]
	if not ex then return false end

	-- ── Parry reflect ────────────────────────────────────────────────────────
	if ex.InParryWindow then
		ex.InParryWindow = false
		print(("[HollowedService] %s PARRIED hit from %s — reflecting!"):format(instanceId, attacker and attacker.Name or "?"))
		if attacker then
			local char = attacker.Character
			if char and char.Parent then
				local reflected = math.floor(damage * PARRY_REFLECT_MULT)
				local existing  = (char:GetAttribute("IncomingHPDamage") or 0) :: number
				char:SetAttribute("IncomingHPDamage", existing + reflected)
				char:SetAttribute("IncomingHPDamageSource", instanceId .. "_Parry")
				local ep = (char:GetAttribute("IncomingPostureDamage") or 0) :: number
				char:SetAttribute("IncomingPostureDamage", ep + (postureDamage or 0) * 2)
				char:SetAttribute("IncomingPostureDamageSource", instanceId .. "_Parry")
			end
		end
		return true  -- mob takes no damage
	end

	-- ── Block: posture only ──────────────────────────────────────────────────
	if data.State == "Blocking" then
		if postureDamage then
			data.CurrentPoise = math.max(0, data.CurrentPoise - postureDamage)
		end
		print(("[HollowedService] %s BLOCKED hit"):format(instanceId))
		ex.PlayerThreat = (ex.PlayerThreat or 0) + THREAT_HIT_ADD * 0.5
		_UpdateVisuals(instanceId)
		return true
	end

	-- ── Normal hit ───────────────────────────────────────────────────────────
	ex.PlayerThreat = (ex.PlayerThreat or 0) + THREAT_HIT_ADD

	data.CurrentHealth = math.max(0, data.CurrentHealth - damage)

	if postureDamage then
		data.CurrentPoise = math.max(0, data.CurrentPoise - postureDamage)
		if data.CurrentPoise <= 0 then
			data.State = "Staggered"
			_intentMap[instanceId] = ""
			local diff     = data.Difficulty or 1
			local diffN    = math.clamp(diff / 10, 0, 1)
			local staggerT = 0.4 - 0.2 * diffN
			print(("[HollowedService] %s STAGGERED %.2fs"):format(instanceId, staggerT))
			task.delay(staggerT, function()
				if _instances[instanceId] and _instances[instanceId].State == "Staggered" then
					_instances[instanceId].State      = _instances[instanceId].Target and "Aggro" or "Patrol"
					_instances[instanceId].CurrentPoise = config.MaxPoise
					local m = _models[instanceId]
					if m then _RestoreSpeed(m, config.MoveSpeed) end
				end
			end)
		end
	end

	_UpdateVisuals(instanceId)
	print(("[HollowedService] %s -%d HP → %d/%d"):format(instanceId, damage, data.CurrentHealth, data.MaxHealth))

	if data.CurrentHealth <= 0 then
		data.KillerId = attacker and attacker.UserId or nil
		data.State    = "Dead"; data.IsActive = false; data.Target = nil
		local m = _models[instanceId]
		if m then _StopMovement(m) end
		_UpdateVisuals(instanceId)
		print(("[HollowedService] %s died → +%d Resonance"):format(instanceId, config.ResonanceGrant))
		if attacker and ProgressionService then
			ProgressionService.GrantResonance(attacker, config.ResonanceGrant, "Hollowed")
		end
		task.delay(config.RespawnDelay, function()
			if not _instances[instanceId] then return end
			data.CurrentHealth   = config.MaxHealth
			data.MaxHealth       = config.MaxHealth
			data.State           = "Patrol"; data.Target = nil
			data.PatrolTarget    = nil; data.PatrolWaitUntil = 0
			data.KillerId        = nil; data.IsActive = true
			local ex = _ext[instanceId]
			if ex then
				ex.PlayerThreat   = 0
				ex.ComboAvailable = false
				ex.InParryWindow  = false
			end
			local mdl = _models[instanceId]
			if mdl then
				local rp = _GetRoot(mdl)
				if rp then
					local off = data.SpawnCFrame.Position - rp.Position
					mdl:PivotTo((rp.CFrame :: CFrame) + off)
				end
				_RestoreSpeed(mdl, config.MoveSpeed)
			end
			_UpdateVisuals(instanceId)
			print(("[HollowedService] %s respawned"):format(instanceId))
		end)
		return false
	end

	return true
end

function HollowedService.GetInstanceData(instanceId: string): HollowedData?
	return _instances[instanceId]
end

function HollowedService.GetAllInstances(): {[string]: HollowedData}
	return _instances
end

-- ─── Spawning ─────────────────────────────────────────────────────────────────

local function _CountInArea(area: string): number
	local n = 0
	for id, a in _instanceAreaMap do
		if a == area and _instances[id] and _instances[id].State ~= "Dead" then n += 1 end
	end
	return n
end

local function _TrySpawnRespawns()
	local variants = {"basic_hollowed","ironclad_hollowed","silhouette_hollowed","resonant_hollowed","ember_hollowed"}
	for _, zone in _spawnerConfig.SpawnZones do
		local cur = _CountInArea(zone.AreaName)
		if cur < zone.MobCap and math.random() < 0.3 then
			local pos = SpawnerConfig.FindSafeSpawnPosition(zone, _instances,
				_spawnerConfig.CollisionCheckRadius, _spawnerConfig.MinSpawnDistance, 5)
			if pos then
				local v  = variants[math.random(1, #variants)]
				local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(math.random(0,360)), 0)
				local id = HollowedService.SpawnInstance(v, cf)
				_instanceAreaMap[id] = zone.AreaName
			end
		end
	end
end

function HollowedService.SetSpawnerConfig(cfg: SpawnerConfig.SpawnerConfig)
	_spawnerConfig = cfg
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function HollowedService:Init(deps: {[string]: any}?)
	if deps then
		ProgressionService = deps.ProgressionService
		PostureService     = (deps :: any).PostureService
	end
	HollowedService._initialized = true
	print("[HollowedService] Initialized")
end

function HollowedService:Start()
	assert(HollowedService._initialized, "Call Init() first")
	if not PostureService then
		local ok, s = pcall(require, game:GetService("ServerScriptService").Server.services.combat.PostureService)
		if ok then PostureService = s end
	end

	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		local now = tick()
		for instanceId, data in _instances do
			local aiTick = GetAITickForDiff(data.Difficulty or 1)
			if now - data.LastAITick >= aiTick then
				data.LastAITick = now
				local ok, err = pcall(_TickAI, instanceId, aiTick)
				if not ok then
					warn(("[HollowedService] AI error %s: %s"):format(instanceId, tostring(err)))
				end
			end
		end
		if now - _lastSpawnCheckTime >= _spawnerConfig.RespawnCheckInterval then
			_lastSpawnCheckTime = now
			_TrySpawnRespawns()
		end
	end)
	print("[HollowedService] Started")
end

function HollowedService:Shutdown()
	if _heartbeatConn then _heartbeatConn:Disconnect(); _heartbeatConn = nil end
	for id in _instances do HollowedService.DespawnInstance(id) end
	print("[HollowedService] Shutdown")
end

return HollowedService