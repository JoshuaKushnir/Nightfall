--!strict
--[[
	ActionController.lua

	Issue #8: Action Controller (Animation & Feel)
	Epic: Phase 2 - Combat & Fluidity

	Client-side controller managing animations, hit-stop, camera shake, and game feel.
	Server-authoritative validation prevents animation spoofing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local ActionTypes = require(ReplicatedStorage.Shared.types.ActionTypes)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local AnimationLoader = require(ReplicatedStorage.Shared.modules.AnimationLoader)
local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)
local WeaponRegistry = require(ReplicatedStorage.Shared.modules.WeaponRegistry)
local Blackboard        = require(ReplicatedStorage.Shared.modules.MovementBlackboard)
local CombatBlackboard  = require(ReplicatedStorage.Shared.modules.CombatBlackboard)

-- WeaponController is injected via dependencies in :Init() to avoid a
-- circular-require (WeaponController is a client controller, not shared).
local WeaponController: any = nil

type ActionConfig = ActionTypes.ActionConfig
type Action = ActionTypes.Action

local ActionController = {}

-- References
local Player = Players.LocalPlayer
local Character: Model?
local Humanoid: Humanoid?
local AnimationController: Animator?
local MovementController: any = nil
local StateSyncController: any = nil -- injected; used for stun-buffer drain
local CombatController: any = nil -- will be injected to track combat state

-- State
local CurrentAction: Action?
local ActionQueue: {ActionConfig} = {}
local ActionCooldowns: {[string]: number} = {}
local LastActionTime = 0
local LastLungeAttackTime = 0 -- Track lunge cooldown

-- Input buffer: stores one Attack/Dodge action pressed during a Stun window.
-- Drained (replayed) the moment the Stun state exits via StateChangedSignal.
local STUN_BUFFER_WINDOW: number = 0.5 -- seconds before buffered action expires
type StunBufferEntry = { config: ActionConfig, expiresAt: number }
local StunBuffer: StunBufferEntry? = nil

-- Combo State
local ComboCount = 0
local LastComboTime = 0
local COMBO_TIMEOUT = 1.5 -- Reset combo if no attack within 1.5 seconds
local COMBO_FINISH_COOLDOWN = 0.6 -- Cooldown after completing 5-hit combo

-- Constants
local MIN_ACTION_INTERVAL = 0.1
local BETWEEN_ATTACK_DELAY = 0.08 -- Brief pause between chained attacks (weight/impact feel)
local PER_SWING_COOLDOWN   = 0.6  -- base minimum gap between swings (weapon speed will reduce this)
local MAX_QUEUE_SIZE = 1 -- Limit action queue to prevent spam stacking

--[[
	Initialize the controller with character and dependencies
]]
function ActionController:Init(dependencies: {[string]: any}?)
	print("[ActionController] Initializing...")

	-- Store dependency references
	if dependencies then
		MovementController  = dependencies.MovementController
		WeaponController    = dependencies.WeaponController
		StateSyncController = dependencies.StateSyncController
		CombatController    = dependencies.CombatController
	end

	-- Wait for character
	if not Player then
		error("[ActionController] LocalPlayer not found")
	end

	Character = Player.Character or Player.CharacterAdded:Wait()
	local humanoid = Character:WaitForChild("Humanoid", 5)
	if not humanoid then
		error("[ActionController] Character missing Humanoid")
	end
	Humanoid = humanoid :: Humanoid

	-- Ensure Animator exists on the Humanoid (standard R15 setup)
	local animator = Humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		warn("[ActionController] Animator not found on Humanoid - creating one")
		animator = Instance.new("Animator")
		animator.Parent = Humanoid
	end
	AnimationController = animator

	print(`[ActionController] Character ready: {Character.Name}`)
end

--[[
	Start the controller
]]
function ActionController:Start()
	print("[ActionController] Starting...")

	-- Wire StateChangedSignal to drain the stun buffer when Stun ends
	if StateSyncController then
		local sig = StateSyncController.GetStateChangedSignal()
		if sig then
			sig:Connect(function(oldState: string, newState: string)
				if oldState ~= "Stunned" then return end
				if newState == "Stunned" then return end
				local buf = StunBuffer
				StunBuffer = nil
				if buf and tick() < buf.expiresAt then
					print("[ActionController] Stun ended — draining buffer: " .. buf.config.Name)
					-- task.defer lets the state fully settle before we re-enter PlayAction
					task.defer(function()
						ActionController.PlayAction(buf.config)
					end)
				else
					if buf then
						print("[ActionController] Stun buffer expired: " .. buf.config.Name)
					end
				end
			end)
		end
	end

	-- Bind input for testing
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		print(`[ActionController INPUT] Key: {input.KeyCode}, MouseButton: {input.UserInputType}, GameProcessed: {gameProcessed}`)

		if gameProcessed then
			print("[ActionController INPUT] Ignoring - GUI has focus")
			return
		end

		-- Mock actions for testing
		-- Left click to light attack
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			print("[ActionController INPUT] LIGHT ATTACK triggered")
			ActionController.PlayAction(ActionTypes.ATTACK_LIGHT)
		-- Middle click or R key to heavy attack
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 or input.KeyCode == Enum.KeyCode.R then
			print("[ActionController INPUT] HEAVY ATTACK triggered")
			ActionController.PlayAction(ActionTypes.ATTACK_HEAVY)
		-- Q to dodge
		elseif input.KeyCode == Enum.KeyCode.Q then
			print("[ActionController INPUT] DODGE triggered")
			ActionController.PlayAction(ActionTypes.DODGE)
		-- F to parry
		elseif input.KeyCode == Enum.KeyCode.F then
			print("[ActionController INPUT] PARRY/BLOCK triggered")
			ActionController.PlayAction(ActionTypes.PARRY)
			task.delay(0.3, function()
				if UserInputService:IsKeyDown(Enum.KeyCode.F) then
					ActionController.PlayAction(ActionTypes.BLOCK)
				end
			end)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.F then
			-- Release block by ending the current action if it's a block
			if CurrentAction and CurrentAction.Config.Type == "Block" then
				CurrentAction:Stop()
				CurrentAction:Cleanup()
				CurrentAction = nil
			end
		end
	end)

	-- Update loop
	local lastUpdate = tick()
	game:GetService("RunService").RenderStepped:Connect(function()
		local now = tick()
		local deltaTime = now - lastUpdate
		lastUpdate = now

		-- Update cooldowns
		for actionId, cooldownEnd in pairs(ActionCooldowns) do
			if now >= cooldownEnd then
				ActionCooldowns[actionId] = nil
			end
		end

		-- Update current action
		if CurrentAction then
			ActionController._UpdateAction(deltaTime)
		end
	end)

	print("[ActionController] Started")
end

--[[
	Helper function to get the correct roll type based on move direction
	@param moveDir Movement direction vector
	@return string, string Folder name and asset name (e.g. "Front Roll", "FrontRoll")
]]
local function GetRollForDirection(moveDir: Vector3): (string, string)
	if moveDir.Magnitude < 0.1 then
		-- No movement, default to front roll
		return "Front Roll", "FrontRoll"
	end

	-- Get character's forward direction
	if not Character or not Character.PrimaryPart then
		return "Front Roll", "FrontRoll"
	end

	local lookVector = Character.PrimaryPart.CFrame.LookVector
	local rightVector = Character.PrimaryPart.CFrame.RightVector

	-- Project movement onto character's forward/right axes
	local forwardDot = moveDir:Dot(lookVector)
	local rightDot = moveDir:Dot(rightVector)

	-- Determine dominant direction
	if math.abs(forwardDot) > math.abs(rightDot) then
		-- Forward or backward
		if forwardDot > 0 then
			return "FrontRoll", "FrontRoll"
		else
			return "BackRoll", "BackRoll"
		end
	else
		-- Left or right
		if rightDot > 0 then
			return "RightRoll", "RightRoll"
		else
			return "LeftRoll", "LeftRoll"
		end

	return "FrontRoll", "FrontRoll"
	end
end

--[[
	Play an action (request to server)
	@param config The action configuration
]]
function ActionController.PlayAction(config: ActionConfig)
	print(`[ActionController] PlayAction called: {config.Name} (Id: {config.Id}) (Type: {config.Type})`)

	-- Validate character
	if not Character or not Humanoid or Humanoid.Health <= 0 then
		print(`[ActionController] ✗ Cannot play action - Character: {if Character then "yes" else "NO"}, Humanoid: {if Humanoid then "yes" else "NO"}, Health: {if Humanoid then Humanoid.Health else "N/A"}`)
		return
	end

	-- Gate attack actions: require an equipped weapon (fists counts).
	if (config.Type == "Attack") and WeaponController and not WeaponController.GetEquipped() then
		print("[ActionController] ✗ Cannot attack — no weapon equipped")
		return
	end

	-- For dodge actions, determine roll direction based on current input (real-time)
	if config.Type == "Dodge" then
		-- Get current move input direction (not cached) - always check, don't depend on MovementController
		local camera = workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			local forward = Vector3.new(look.X, 0, look.Z).Unit
			if forward.Magnitude < 0.1 then
				forward = Vector3.new(0, 0, -1)
			end
			local right = Vector3.new(-forward.Z, 0, forward.X)
			local x, z = 0, 0
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
			local moveDir = forward * z + right * x
			
			if moveDir.Magnitude > 0 then
				moveDir = moveDir.Unit
			else
				moveDir = Vector3.new(0, 0, 0)
			end
			
			local rollFolder, rollAsset = GetRollForDirection(moveDir)
			print(`[ActionController] Dodge direction: {rollFolder}/{rollAsset} (moveDir magnitude: {moveDir.Magnitude})`)

			-- Clone config and update both folder and asset names
			config = table.clone(config)
			config.AnimationName = rollFolder
			config.AnimationAssetName = rollAsset
		end
	end
		-- For light attacks, handle combo system and check for lunge
	if config.Id == "atk_light" then
		-- Check if sprinting (use lunge attack instead)
		local isCurrentlySprinting = MovementController and MovementController._isSprinting() or false
		if isCurrentlySprinting then
			-- Check lunge cooldown (use config cooldown to prevent spam)
			local now = tick()
			local lungeCooldown = ActionTypes.LUNGE_ATTACK.Cooldown or 1.2
			if now - LastLungeAttackTime > lungeCooldown then
				print("[ActionController] Lunge attack triggered (sprinting + attack)")

				-- QUICK-FIX: pre-emptively apply client impulse here so movement is visible
				-- even if later prediction/animation timing is delayed or overwritten.
				if MovementController and MovementController.ApplyImpulse then
					local camera = workspace.CurrentCamera
					local forward = Vector3.new(0, 0, -1)
					if camera then
						local look = camera.CFrame.LookVector
						forward = Vector3.new(look.X, 0, look.Z)
						if forward.Magnitude < 0.1 then
							forward = Vector3.new(0, 0, -1)
						end
						forward = forward.Unit
					end

					local LUNGE_SPEED = (MovementConfig and MovementConfig.Movement and MovementConfig.Movement.LungeSpeed) or 45

					-- Ensure the pre-emptive impulse covers the lunge's hit window so the
					-- visible forward burst is still present when the hit frame occurs.
					local lungeCfg = ActionTypes.LUNGE_ATTACK
					local hitTime = (lungeCfg.HitStartFrame and (lungeCfg.Duration * lungeCfg.HitStartFrame)) or (lungeCfg.Duration * 0.4)
					local preemptDur = math.clamp(hitTime + 0.12, 0.12, 0.6)

					local applied = MovementController.ApplyImpulse(forward, LUNGE_SPEED, preemptDur, "lunge_preempt")
					print("[ActionController] Pre-emptive ApplyImpulse at PlayAction returned: " .. tostring(applied) .. " (dur=" .. tostring(preemptDur) .. ")")
				end

				ActionController.PlayAction(ActionTypes.LUNGE_ATTACK)
				LastLungeAttackTime = now
				return
			end
		end
		
		local now = tick()

		-- Reset combo if timeout
		if now - LastComboTime > COMBO_TIMEOUT then
			ComboCount = 0
		end

		-- ── Weapon-aware combo tree (Issue #71) ───────────────────────────────
		-- If the player has a weapon equipped attempt to use that weapon's
		-- Animations.Combo table.  Fall back to bare-hands punch N on no weapon.
		local weaponId: string? = WeaponController and WeaponController.GetEquipped() or nil
		local weaponCfg: any? = weaponId and WeaponRegistry.Has(weaponId) and WeaponRegistry.Get(weaponId) or nil
		-- attack speed multiplier from the weapon (1.0 = baseline)
		local speed = 1
		if weaponCfg and weaponCfg.AttackSpeed and weaponCfg.AttackSpeed > 0 then
			speed = weaponCfg.AttackSpeed
		end
		-- store speed on config so _PlayActionLocal can record it on the action
		config.Speed = speed

		local maxCombo: number
		if weaponCfg and weaponCfg.Animations and weaponCfg.Animations.Combo and #weaponCfg.Animations.Combo > 0 then
			maxCombo = #weaponCfg.Animations.Combo
		else
			maxCombo = 5 -- bare-hands default
		end

		-- Increment combo (attacks count toward the combo chain)
		ComboCount = ComboCount + 1
		if ComboCount > maxCombo then
			ComboCount = 1
		end

		LastComboTime = now
		-- keep blackboard synchronized so other systems can read combo state
		CombatBlackboard.ComboCount = ComboCount
		CombatBlackboard.ComboExpiry = now + COMBO_TIMEOUT

		-- Clone config and apply animation
		config = table.clone(config)

		if weaponCfg and weaponCfg.Animations and weaponCfg.Animations.Combo and weaponCfg.Animations.Combo[ComboCount] then
			-- Weapon combo: use Folder/Asset pair from the weapon definition
			local comboEntry = weaponCfg.Animations.Combo[ComboCount]
			config.AnimationName      = comboEntry.Folder
			config.AnimationAssetName = comboEntry.Asset

			-- Rescale duration by the weapon's AttackSpeed multiplier (< 1 = faster)
			if weaponCfg.AttackSpeed and weaponCfg.AttackSpeed > 0 then
				config.Duration = config.Duration / weaponCfg.AttackSpeed
			end

			-- Apply weapon base damage
			if weaponCfg.BaseDamage then
				config.Damage = weaponCfg.BaseDamage
			end

			print(`[ActionController] Weapon combo {ComboCount}/{maxCombo} ({weaponId}) - {config.AnimationName}/{config.AnimationAssetName}`)
		else
			-- Bare-hands fallback: reuse legacy punch N animation names
			config.AnimationAssetName = `punch {ComboCount}`
			print(`[ActionController] Bare-hands combo {ComboCount}/{maxCombo} - {config.AnimationAssetName}`)
		end

		-- Mark finisher on the last combo hit
		if ComboCount == maxCombo then
			config.IsFinisher = true
			config.KnockbackPower = (weaponCfg and (weaponCfg.KnockbackPower or 1.0) * 50) or 50
			-- NOTE: cooldown is set AFTER the finisher action completes, not here.
			-- Setting it here would block the action before it even plays.
		else
			config.IsFinisher = false
			config.KnockbackPower = 0  -- Explicitly zero knockback on non-finisher hits
		end
	end
		-- ── Stun input buffer ────────────────────────────────────────────────────
	-- If the player is Stunned, buffer Attack/Dodge actions instead of dropping them.
	-- The buffer is a single slot (last pressed wins). It drains when Stun ends.
	local currentState = StateSyncController and StateSyncController.GetCurrentState() or nil
	if currentState == "Stunned" then
		if config.Type == "Attack" or config.Type == "Dodge" then
			StunBuffer = { config = config, expiresAt = tick() + STUN_BUFFER_WINDOW }
			print(("[ActionController] Buffered '%s' during Stun (window %.1fs)"):format(
				config.Name, STUN_BUFFER_WINDOW))
		end
		-- Always silently discard while Stunned — let the buffer handle replay.
		return
	end

	-- Throttle rapid requests
	if tick() - LastActionTime < MIN_ACTION_INTERVAL then
		print(`[ActionController] Throttled - too soon`)
		return
	end

	-- Check cooldown
	if ActionCooldowns[config.Id] and tick() < ActionCooldowns[config.Id] then
		print(`[ActionController] Action on cooldown: {config.Id}`)
		return
	end

	-- compute weapon speed for attacks (used later for cd and playback)
	if config.Type == "Attack" then
		local weaponId: string? = WeaponController and WeaponController.GetEquipped() or nil
		local weaponCfg: any? = weaponId and WeaponRegistry.Has(weaponId) and WeaponRegistry.Get(weaponId) or nil
		local speed = 1
		if weaponCfg and weaponCfg.AttackSpeed and weaponCfg.AttackSpeed > 0 then
			speed = weaponCfg.AttackSpeed
		end
		config.Speed = speed
		-- apply cooldown immediately so queued requests also respect it
		local cd = PER_SWING_COOLDOWN / speed
		if config.IsFinisher then
			cd = COMBO_FINISH_COOLDOWN / speed
		end
		ActionCooldowns[config.Id] = tick() + cd
	end

	-- Special handling for movement actions (Dodge) - prevent spam queueing
	if config.Type == "Dodge" then
		-- Don't queue dodge if currently dodging
		if CurrentAction and CurrentAction.Config.Type == "Dodge" then
			print(`[ActionController] Cannot dodge while already dodging`)
			return
		end

		-- Don't queue dodge if another dodge is already queued
		for _, queuedAction in ipairs(ActionQueue) do
			if queuedAction.Type == "Dodge" then
				print(`[ActionController] Dodge already queued, ignoring duplicate`)
				return
			end
		end

		-- Apply cooldown immediately when dodge starts (not after it finishes)
		if config.Cooldown then
			ActionCooldowns[config.Id] = tick() + config.Cooldown
		end
	end

	-- Queue or play immediately
	if CurrentAction then
		-- Debounce: do not queue a second Attack while one is active
		if CurrentAction.Config.Type == "Attack" and config.Type == "Attack" then
		-- allow chaining same attack (combo) but prevent mixing light/heavy
		if CurrentAction.Config.Id ~= config.Id then
			print("[ActionController] Cannot queue a second attack while another attack type is active")
			return
		end
	end
		-- Check if queue is full
		if #ActionQueue >= MAX_QUEUE_SIZE then
			print(`[ActionController] Action queue full ({MAX_QUEUE_SIZE}), ignoring {config.Name}`)
			return
		end

		-- Only allow certain actions to queue during certain states
		-- Dodge and Ability actions can queue during attacks for smooth transitions
		if config.Type == "Dodge" or config.Type == "Attack" or config.Type == "Ability" then
			table.insert(ActionQueue, config)
			print(`[ActionController] Action queued: {config.Name} ({#ActionQueue}/{MAX_QUEUE_SIZE})`)
		else
			print(`[ActionController] Cannot queue {config.Type} while {CurrentAction.Config.Type} is active`)
		end
	else
		print(`[ActionController] Playing action locally: {config.Name}`)
		-- notify combat controller of start
		if CombatController then
			CombatController.NotifyActionStarted(config)
		end
		ActionController._PlayActionLocal(config)

		-- Notify server
		local networkEvent = NetworkProvider:GetRemoteEvent("StateRequest")
		if networkEvent then
			networkEvent:FireServer({
				Type = "ActionStart",
				ActionId = config.Id,
				Timestamp = tick(),
			})
		end

		LastActionTime = tick()
	end
end

--[[
	Play an action locally (client-side prediction)
	@param config The action configuration
]]
function ActionController._PlayActionLocal(config: ActionConfig)
	if not Character or not Humanoid then
		print("[ActionController] Cannot play action - missing character components")
		return
	end

	print(`[ActionController] ===== PLAYING ACTION: {config.Name} (Duration: {config.Duration}s) =====`)

	-- ── Create action object ──────────────────────────────────────────────
	local action: Action = {
		Config = config,
		Speed = config.Speed or 1,
		StartTime = tick(),
		EndTime = tick() + config.Duration,
		IsActive = true,
		TargetHit = nil,
		AnimationTrack = nil,
		Hitbox = nil,

		Play = function(self: Action)
			if self.AnimationTrack then
				self.AnimationTrack:Play()
			end
		end,

		Stop = function(self: Action)
			if self.AnimationTrack then
				self.AnimationTrack:Stop(0.1)
			end
			self.IsActive = false
		end,

		OnFrame = function(self: Action, deltaTime: number) end,

		Cleanup = function(self: Action)
			if self.AnimationTrack then
				self.AnimationTrack:Destroy()
				self.AnimationTrack = nil
			end
			if self.Hitbox then
				HitboxService.RemoveHitbox(self.Hitbox)
				self.Hitbox = nil
			end
			-- Clear casting flag when a spell action ends
			if self.Config and self.Config.Type == "Ability" then
				CombatBlackboard.IsCasting = false
			end
			-- inform combat controller that the action finished
			if CombatController and self.Config then
				CombatController.NotifyActionEnded(self.Config)
			end
		end,
	}

	CurrentAction = action

	-- Track spell-casting state on the shared blackboard
	if config.Type == "Ability" then
		CombatBlackboard.IsCasting = true
		CombatBlackboard.LastActionType = "Ability"
	elseif config.Type == "Attack" then
		CombatBlackboard.LastActionType = "Attack"
	elseif config.Type == "Dodge" then
		CombatBlackboard.LastActionType = "Dodge"
	end

	-- Special handling for dodge: non-collidable movement to avoid fling
	if config.Type == "Dodge" then
		local rootPart = Utils.GetRootPart(Player)
		if rootPart and Character then
			local dodgeStartTime = tick()
			local dodgeDuration = config.Duration
			-- ensure we aren't already overlapping something by stepping back a bit
			local dodgeDir = rootPart.CFrame.LookVector
			if rootPart and rootPart:IsA("BasePart") then
				local function isOverlapping(): boolean
					for _, p in ipairs(rootPart:GetTouchingParts()) do
						if not p:IsDescendantOf(Character) then
							return true
						end
					end
					return false
				end
				if isOverlapping() then
					rootPart.CFrame = rootPart.CFrame - (dodgeDir * 1.5)
				end
			end

			-- ── Disable CanCollide on EVERY BasePart in character ──────────
			-- HumanoidRootPart alone is not enough; arms/legs still collide
			-- and cause flings when brushing another character's physics body.
			local savedCollide: { [BasePart]: boolean } = {}
			for _, part in ipairs(Character:GetDescendants()) do
				if part:IsA("BasePart") then
					local bp = part :: BasePart
					savedCollide[bp] = bp.CanCollide
					bp.CanCollide = false
				end
			end
			print("[ActionController] Dodge: CanCollide disabled on all character parts")

			-- No longer cache velocity; read every frame so fallback updates are respected
			-- also track last safe CFrame to avoid popping into objects when collisions
			local lastSafeCFrame = rootPart.CFrame

			action.OnFrame = function(self: Action, deltaTime: number)
				if not rootPart or not rootPart.Parent then return end
				-- We rely on MovementController's BodyVelocity (physics) for the actual movement.
				-- Tracking lastSafeCFrame prevents clipping through walls when collisions re-enable.
				local overlapping = false
				for _, p in ipairs(rootPart:GetTouchingParts()) do
					if not p:IsDescendantOf(Character) then
						overlapping = true
						break
					end
				end
				if not overlapping then
					lastSafeCFrame = rootPart.CFrame
				end
			end

			-- Restore CanCollide for ALL parts on cleanup
			local originalCleanup = action.Cleanup
			action.Cleanup = function(self: Action)
				-- if we overlapped anything during the dodge, slide back to last safe spot
				-- before re-enabling collisions to avoid post-dodge flings.
				if rootPart and lastSafeCFrame then
					rootPart.CFrame = lastSafeCFrame
				end
				
				for bp, original in pairs(savedCollide) do
					if bp and bp.Parent then
						bp.CanCollide = original
					end
				end
				print("[ActionController] Dodge: CanCollide restored on all character parts")
				-- if re-enabling put us inside something, nudge backwards along dodgeDir
				if rootPart and dodgeDir and dodgeDir.Magnitude > 0.1 then
					local tries = 0
					while tries < 5 do
						local overlapping = false
						for _, p in ipairs(rootPart:GetTouchingParts()) do
							if not p:IsDescendantOf(Character) then
								overlapping = true
								break
							end
						end
						if not overlapping then break end
						rootPart.CFrame = rootPart.CFrame - dodgeDir.Unit * 0.5
						tries += 1
					end
				end
				originalCleanup(self)
			end
		end
	end

	-- Track dodge in Blackboard (readable by MovementController dispatcher and VFX)
	if config.Type == "Dodge" then
		Blackboard.IsDodging = true
	end

	-- ── Movement modifier (attacks slow player slightly) ─────────────────
	if config.Type == "Attack" and MovementController and MovementController.SetModifier then
		MovementController.SetModifier("Attacking", 0.75)
	end

	-- ── Animation ─────────────────────────────────────────────────────────
	local track: AnimationTrack? = nil

	if AnimationController and Humanoid then
		-- Prefer named project animation
		if config.AnimationName and config.AnimationName ~= "" then
			track = AnimationLoader.LoadTrack(Humanoid, config.AnimationName, config.AnimationAssetName)
		end
		-- Fallback to raw AnimationId
		if not track and config.AnimationId and config.AnimationId ~= "" then
			local anim = Instance.new("Animation")
			anim.AnimationId = config.AnimationId
			local ok, loaded = pcall(function() return AnimationController:LoadAnimation(anim) end)
			if ok and loaded then
				track = loaded :: AnimationTrack
			else
				anim:Destroy()
			end
		end
	end

	if track then
		track.Priority = config.AnimationPriority or Enum.AnimationPriority.Action
		if config.AnimationSpeed then
			track:AdjustSpeed(config.AnimationSpeed)
		end
		action.AnimationTrack = track
		action:Play()
		print(`[ActionController] ✓ Animation playing: {config.Name}`)
	else
		print(`[ActionController] ⚠ No animation for {config.Name} — proceeding without`)
	end

	-- ── OnStart callback ──────────────────────────────────────────────────
	if config.OnStart then
		task.spawn(config.OnStart, Player)
	end

	-- ── Attack: small forward nudge to make swings feel aggressive ────────
	if config.Type == "Attack" and config.Id ~= "atk_lunge"
		and config.AttackImpulse and config.AttackImpulse > 0
		and MovementController and MovementController.ApplyImpulse then
		local rootPart = Utils.GetRootPart(Player)
		if rootPart then
			local forward = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
			local cam = workspace.CurrentCamera
			if cam then
				local look = cam.CFrame.LookVector
				local cf = Vector3.new(look.X, 0, look.Z)
				if cf.Magnitude > 0.1 then forward = cf.Unit end
			end
			if forward.Magnitude > 0.1 then
				MovementController.ApplyImpulse(forward, config.AttackImpulse, 0.12, "attack_nudge")
			end
		end
	end

	-- ── Dodge: directional impulse + iframes ──────────────────────────────
	if config.Type == "Dodge" then
		local rootPart = Utils.GetRootPart(Player)
		-- use outer dodgeDir variable (initialized earlier) and update based on input
		dodgeDir = (rootPart and rootPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
		-- secondary overlap check using final dodgeDir
		if rootPart and rootPart:IsA("BasePart") then
			local function isOverlapping(): boolean
				for _, p in ipairs(rootPart:GetTouchingParts()) do
					if not p:IsDescendantOf(Character) then
						return true
					end
				end
				return false
			end
			if isOverlapping() then
				rootPart.CFrame = rootPart.CFrame - (dodgeDir * 1.5)
			end
		end

		-- Resolve direction from current input + camera
		local cam = workspace.CurrentCamera
		if cam and rootPart then
			local look = cam.CFrame.LookVector
			local fwd = Vector3.new(look.X, 0, look.Z)
			if fwd.Magnitude > 0.1 then
				fwd = fwd.Unit
				local right = Vector3.new(-fwd.Z, 0, fwd.X)
				local x, z = 0, 0
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
				local moveDir = fwd * z + right * x
				if moveDir.Magnitude > 0 then dodgeDir = moveDir.Unit end
			end
		end

		-- Apply impulse
		local DODGE_SPEED = (MovementConfig.Dodge and MovementConfig.Dodge.Speed) or 65
		local DODGE_DUR   = math.min(config.Duration, (MovementConfig.Dodge and MovementConfig.Dodge.Duration) or config.Duration)
		local didApply = MovementController and MovementController.ApplyImpulse
			and MovementController.ApplyImpulse(dodgeDir, DODGE_SPEED, DODGE_DUR, "dodge")

		if not didApply and rootPart then
			print("[ActionController] Dodge: ApplyImpulse failed")
		end

		-- FOV punch
		if MovementConfig.Camera and MovementConfig.Camera.FOVPunchEnabled then
			task.spawn(function()
				local cam2 = workspace.CurrentCamera
				if not cam2 then return end
				local startFOV = cam2.FieldOfView
				cam2.FieldOfView = startFOV + 12
				local t0 = tick()
				while tick() - t0 < config.Duration and cam2 do
					cam2.FieldOfView = startFOV + 12 * (1 - (tick() - t0) / config.Duration)
					task.wait(0.05)
				end
				if cam2 then cam2.FieldOfView = startFOV end
			end)
		end

		-- Tell server: Dodging → Idle
		local stateEvent = NetworkProvider:GetRemoteEvent("StateRequest")
		if stateEvent then
			stateEvent:FireServer({ Type = "SetState", State = "Dodging", Timestamp = tick() })
			task.delay(config.Duration, function()
				stateEvent:FireServer({ Type = "SetState", State = "Idle", Timestamp = tick() })
			end)
		end
	end

	-- ── Lunge: forward burst ──────────────────────────────────────────────
	if config.Type == "Attack" and config.Id == "atk_lunge" then
		local rootPart = Utils.GetRootPart(Player)
		if rootPart then
			local cam = workspace.CurrentCamera
			local forward = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
			if cam then
				local look = cam.CFrame.LookVector
				local cf = Vector3.new(look.X, 0, look.Z)
				if cf.Magnitude > 0.1 then forward = cf.Unit end
			end
			if forward.Magnitude > 0.1 then forward = forward.Unit end

			local LUNGE_SPEED = (MovementConfig and MovementConfig.Movement and MovementConfig.Movement.LungeSpeed) or 45
			local hitTime = (config.HitStartFrame and config.Duration * config.HitStartFrame) or (config.Duration * 0.4)
			local keepTime = math.clamp(hitTime + 0.12, 0.12, 0.6)

			local applied = MovementController and MovementController.ApplyImpulse
				and MovementController.ApplyImpulse(forward, LUNGE_SPEED, keepTime, "lunge")

			-- Fallback BodyVelocity
			if not applied then
				local lv = Instance.new("BodyVelocity")
				lv.Name = "_LungeBodyVelocity"
				lv.MaxForce = Vector3.new(math.huge, 0, math.huge)
				lv.Velocity  = forward * LUNGE_SPEED
				lv.Parent = rootPart
				if rootPart:IsA("BasePart") then
					rootPart.AssemblyLinearVelocity = forward * LUNGE_SPEED
				end
				task.delay(keepTime, function()
					if lv.Parent then
						lv.Velocity = Vector3.new(0, 0, 0)
						lv:Destroy()
					end
				end)
			end
		end
	end

	-- ── Hitbox (attacks only) ─────────────────────────────────────────────
	if config.Type == "Attack" and config.HitStartFrame then
		local hitTime = config.Duration * config.HitStartFrame
		task.delay(hitTime, function()
			if CurrentAction ~= action or not action.IsActive or not Character then return end
			local rootPart = Utils.GetRootPart(Player)
			if not rootPart then return end

			local hitboxConfig = {
				Shape   = "Sphere",
				Owner   = Player,
				Damage  = config.Damage or 10,
				Position = rootPart.Position + rootPart.CFrame.LookVector * 5,
				Size    = Vector3.new(6, 6, 6),
				LifeTime = 1.0,
				OnHit = function(target: any, _hitData: any)
					local targetName: string
					if typeof(target) == "Instance" and target:IsA("Player") then
						targetName = target.Name
					elseif type(target) == "string" then
						targetName = target
					else
						return
					end

					print(`[ActionController] ✓ Hit {targetName} with {config.Name}`)

					-- Finisher knockback
					if config.IsFinisher and typeof(target) == "Instance" and (config.KnockbackPower and config.KnockbackPower > 0) then
						local targetChar = (target :: Player).Character
						if targetChar then
							local tRoot = targetChar:FindFirstChild("HumanoidRootPart")
							local myRoot = Utils.GetRootPart(Player)
							if tRoot and myRoot and tRoot:IsA("BasePart") then
								local dir = (tRoot.Position - myRoot.Position).Unit
								local force = dir * config.KnockbackPower
								tRoot.AssemblyLinearVelocity = Vector3.new(force.X, 20, force.Z)
							end
						end
					end

					-- Server validation
					local ev = NetworkProvider:GetRemoteEvent("StateRequest")
					if ev then
						ev:FireServer({
							Type = "HitRequest",
							Timestamp = tick(),
							ActionId  = config.Id,
							HitData   = {
								TargetName   = targetName,
								Damage       = config.Damage or 10,
								HitType      = config.Type,
								ActionName   = config.Name,
								IsFinisher   = config.IsFinisher or false,
								KnockbackPower = config.KnockbackPower,
							},
						})
					end

					-- Hit-stop only on actual contact
					if config.HitStopDuration and CurrentAction == action then
						ActionController._ApplyHitStop(config.HitStopDuration)
					end
				end,
			}

			action.Hitbox = HitboxService.CreateHitbox(hitboxConfig)
		end)
	end

	print(`[ActionController] ✓ Playing: {config.Name}`)
end

--[[
	Update current action
	@param deltaTime Time since last frame
]]
function ActionController._UpdateAction(deltaTime: number)
	if not CurrentAction then
		return
	end

	local action = CurrentAction

	-- ── Early cancel window ────────────────────────────────────────────────
	-- Once the current action passes its CancelFrame fraction, allow a queued
	-- action to interrupt — this is the core of fluid combo chaining.
	if action.Config.CancelFrame and #ActionQueue > 0 then
		local cancelAt = action.StartTime + action.Config.Duration * action.Config.CancelFrame
		if tick() >= cancelAt then
			-- Fade the current animation out gently so the blend is smooth
			if action.AnimationTrack and action.AnimationTrack.IsPlaying then
				action.AnimationTrack:Stop(0.08)
			end
			action.IsActive = false
			-- Destroy the track slightly later so the fadeout plays
			local dyingTrack = action.AnimationTrack
			action.AnimationTrack = nil
			if dyingTrack then
				task.delay(0.15, function() dyingTrack:Destroy() end)
			end
			-- Release the hitbox if it wasn't fired yet
			if action.Hitbox then
				HitboxService.RemoveHitbox(action.Hitbox)
				action.Hitbox = nil
			end
			-- Clear attack movement penalty
			if action.Config.Type == "Attack" and MovementController and MovementController.SetModifier then
				MovementController.SetModifier("Attacking", 1.0)
			end
			-- Clear dodge Blackboard flag on early cancel
			if action.Config.Type == "Dodge" then
				Blackboard.IsDodging = false
			end
			-- Block fresh spam only during the brief transition gap.  Do not reduce
			-- an existing cooldown (math.max ensures we only push it forward).
			if action.Config.Type == "Attack" then
				local newCd = tick() + BETWEEN_ATTACK_DELAY + 0.01
				ActionCooldowns[action.Config.Id] = math.max(ActionCooldowns[action.Config.Id] or 0, newCd)
			end
			CurrentAction = nil
			local nextConfig = table.remove(ActionQueue, 1)
			print("[ActionController] ⚡ Early cancel → " .. nextConfig.Name)
			if nextConfig.Type == "Attack" then
				-- Brief pause for impact weight before chaining next hit
				task.delay(BETWEEN_ATTACK_DELAY, function()
					if not CurrentAction then
						ActionController._PlayActionLocal(nextConfig)
					end
				end)
			else
				ActionController._PlayActionLocal(nextConfig)
			end
			return
		end
	end

	-- Check if action complete
	if tick() >= action.EndTime then
		print(`[ActionController] Action COMPLETE: {action.Config.Name}`)
		action:Stop()
		action:Cleanup()

		-- Clear dodge Blackboard flag on action complete
		if action.Config and action.Config.Type == "Dodge" then
			Blackboard.IsDodging = false
		end

		-- If this was an attack, clear the movement slowdown modifier
		if action.Config and action.Config.Type == "Attack" and MovementController and MovementController.SetModifier then
			MovementController.SetModifier("Attacking", 1.0)
			print("[ActionController] Removed movement modifier: Attacking")
		end


		CurrentAction = nil

		-- Process queued action
		if #ActionQueue > 0 then
			local nextAction = table.remove(ActionQueue, 1)
			print(`[ActionController] Processing queued action: {nextAction.Name}`)
			if nextAction.Type == "Attack" then
				-- compute speed here as well (same logic as PlayAction)
				local speedLocal = 1
				local wid: string? = WeaponController and WeaponController.GetEquipped() or nil
				local wcfg: any? = wid and WeaponRegistry.Has(wid) and WeaponRegistry.Get(wid) or nil
				if wcfg and wcfg.AttackSpeed and wcfg.AttackSpeed > 0 then
					speedLocal = wcfg.AttackSpeed
				end
				-- Brief pause for impact weight; scale by weapon speed
				task.delay(BETWEEN_ATTACK_DELAY / speedLocal, function()
					if not CurrentAction then
						ActionController._PlayActionLocal(nextAction)
					end
				end)
			else
				ActionController._PlayActionLocal(nextAction)
			end
		end
	else
		action:OnFrame(deltaTime)
	end
end

--[[
	Apply hit-stop (brief freeze effect)
	@param duration Time to freeze (seconds)
]]
function ActionController._ApplyHitStop(duration: number)
	print(`[ActionController] Hit-stop: {duration}s`)

	-- DRAMATIC camera zoom for impact - DISABLED
	-- task.spawn(function()
	-- 	local camera = workspace.CurrentCamera
	-- 	if camera then
	-- 		local startFOV = camera.FieldOfView
	-- 		-- Big zoom in
	-- 		camera.FieldOfView = startFOV - 10
	-- 		task.wait(duration * 0.3)
	-- 		-- Quick zoom out past normal
	-- 		if camera then
	-- 			camera.FieldOfView = startFOV + 3
	-- 			task.wait(duration * 0.7)
	-- 			if camera then
	-- 				camera.FieldOfView = startFOV
	-- 			end
	-- 		end
	-- 	end
	-- end)

	-- Briefly slow down animations for impact feel
	if Humanoid then
		local animator = Humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				local originalSpeed = track.Speed
				track:AdjustSpeed(0.15) -- brief slow-down (15% \u2014 gives impact feel without full freeze)
				task.delay(duration, function()
					if track.IsPlaying then
						track:AdjustSpeed(originalSpeed)
					end
				end)
			end
		end
	end
end

--[[
	Apply camera shake (non-blocking)
	@param trauma Amount of trauma (0-1)
]]
function ActionController._ApplyCameraShake(trauma: number)
	print(`[ActionController] Camera shake: {trauma}`)

	-- Spawn in separate thread to avoid blocking gameplay
	task.spawn(function()
		local camera = workspace.CurrentCamera
		if not camera then return end

		local startCFrame = camera.CFrame

		-- Smooth, elegant camera shake
		for i = 1, 15 do
			local decay = (1 - (i / 15)) ^ 1.5 -- Smoother decay curve
			local intensity = trauma * decay * 1.5 -- Polished intensity

			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)

			-- Gentle rotation shake
			local rotationShake = CFrame.Angles(
				math.rad((math.random() - 0.5) * intensity * 1.5),
				math.rad((math.random() - 0.5) * intensity * 1.5),
				math.rad((math.random() - 0.5) * intensity * 1)
			)

			camera.CFrame = startCFrame * CFrame.new(offset) * rotationShake
			task.wait(0.016)
		end

		camera.CFrame = startCFrame
	end)
end

--[[
	Handle character respawn
	@param newCharacter The new character
]]
function ActionController:OnCharacterAdded(newCharacter: Model)
	print("[ActionController] Character respawned")

	-- Clean up old action
	if CurrentAction then
		-- Ensure any attack slowdown modifier is cleared
		if CurrentAction.Config and CurrentAction.Config.Type == "Attack" and MovementController and MovementController.SetModifier then
			MovementController.SetModifier("Attacking", 1.0)
			print("[ActionController] Removed movement modifier on respawn: Attacking")
		end

		CurrentAction:Stop()
		CurrentAction:Cleanup()
		CurrentAction = nil
	end

	-- Clear queue and cooldowns
	ActionQueue = {}
	ActionCooldowns = {}

	-- Reinitialize
	Character = newCharacter
	local humanoid = Character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn("[ActionController] New character missing Humanoid")
		Humanoid = nil
		AnimationController = nil
	else
		Humanoid = humanoid

		-- Ensure Animator exists on the new Humanoid as well
		local animator = Humanoid:FindFirstChildOfClass("Animator") :: Animator?
		if not animator then
			warn("[ActionController] Animator not found on new Humanoid - creating one")
			animator = Instance.new("Animator")
			animator.Parent = Humanoid
		end
		AnimationController = animator
	end

	print("[ActionController] Ready for new character")
end

--[[
	PlayAbilityAction — cast an Aspect/Expression ability through the unified combat queue.
	This routes spell casts through the same cancel-window and combo pipeline as melee,
	so spells and physical hits chain into each other seamlessly.

	@param abilityId  The ability Id (e.g. "AshenStep", "Current", "Ignite").
	@param targetPos  Optional cast-aim position from the mouse/camera.
]]
function ActionController.PlayAbilityAction(abilityId: string, targetPos: Vector3?)
	if not abilityId or abilityId == "" then return end

	-- === combo bookkeeping ===
	local now = tick()
	if now - LastComboTime > COMBO_TIMEOUT then
		ComboCount = 0
	end
	-- compute same maxCombo as attacks (weapon-aware)
	local maxCombo = 5
	do
		local weaponId: string? = WeaponController and WeaponController.GetEquipped() or nil
		local weaponCfg: any? = weaponId and WeaponRegistry.Has(weaponId) and WeaponRegistry.Get(weaponId) or nil
		if weaponCfg and weaponCfg.Animations and weaponCfg.Animations.Combo and #weaponCfg.Animations.Combo > 0 then
			maxCombo = #weaponCfg.Animations.Combo
		end
	end
	ComboCount = ComboCount + 1
	if ComboCount > maxCombo then
		ComboCount = 1
	end
	LastComboTime = now
	CombatBlackboard.ComboCount = ComboCount
	CombatBlackboard.ComboExpiry = now + COMBO_TIMEOUT

	-- Build a cast-window ActionConfig.
	-- Duration is the commitment window (can't cancel before CancelFrame).
	-- No client-side hitbox — server manages damage application.
	local castConfig: ActionConfig = {
		Id                = "ability_" .. abilityId,
		Name              = abilityId,
		Type              = "Ability",
		AnimationId       = "",
		AnimationName     = "",      -- VFX/animation is server-driven or deferred
		Duration          = 0.55,   -- cast commitment window
		CancelFrame       = 0.65,   -- melee can cancel in after 65% through
		AttackImpulse     = 0,
		IsFinisher        = false,
		KnockbackPower    = 0,
		HitStopDuration   = nil,
		HitStartFrame     = nil,    -- no client hitbox
		-- Cooldown acts as a local rate-limit guard (0.5s) to prevent double-fire
		-- while the server round-trip is in flight. Real cooldown is server-authoritative.
		Cooldown          = 0.5,
		OnStart           = function(_p: Player)
			-- Refresh the melee combo window so physical hits can continue after a spell
			LastComboTime = tick()
			CombatBlackboard.ComboExpiry = LastComboTime + COMBO_TIMEOUT
			-- Fire the server-side ability cast
			NetworkProvider:FireServer("AbilityCastRequest", {
				AbilityId     = abilityId,
				TargetPosition = targetPos,
			})
		end,
	}

	print(("[ActionController] PlayAbilityAction → %s"):format(abilityId))
	ActionController.PlayAction(castConfig)
end

--[[
	GetComboCount — read the current melee combo count (used by UI / other systems).
]]
function ActionController.GetComboCount(): number
	return ComboCount
end

return ActionController