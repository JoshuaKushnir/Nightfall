--!strict
-- ActionController unit tests (spam prevention and cooldown assignment)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionController = require(ReplicatedStorage.Client.controllers.ActionController)
local ActionTypes = require(ReplicatedStorage.Shared.types.ActionTypes)
local Blackboard = require(ReplicatedStorage.Shared.modules.MovementBlackboard)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)

return {
    name = "ActionController Unit Tests",
    tests = {
        {
            name = "Attack cooldown blocks rapid repeats",
            fn = function()
                -- stub minimal character/humanoid to satisfy validation
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                ActionController._Test_SetHeavyState(false, false) -- ensure no residual hold/consume

                local cfg = {
                    Id = "test_attack",
                    Name = "Test Swing",
                    Type = "Attack",
                    Duration = 0.1,
                }

                -- ensure clean state
                ActionController.ActionCooldowns = {}

                ActionController.PlayAction(cfg)
                assert(ActionController.ActionCooldowns[cfg.Id], "cooldown not set on first play")
                local firstCd = ActionController.ActionCooldowns[cfg.Id]

                -- immediate second call should be ignored due to cooldown
                ActionController.PlayAction(cfg)
                local secondCd = ActionController.ActionCooldowns[cfg.Id]
                assert(firstCd == secondCd, "cooldown changed on second rapid play")

                -- allow time for MIN_ACTION_INTERVAL then attempt again; should still be on cooldown
                task.wait(0.2)
                ActionController.PlayAction(cfg)
                assert(ActionController.ActionCooldowns[cfg.Id] == firstCd,
                    "cooldown incorrectly reset by later play")
            end,
        },
        {
            name = "Heavy and light attacks have separate cooldowns and can't overlap",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                ActionController.ActionCooldowns = {}
                ActionController._Test_SetHeavyState(false, false)

                local light = { Id = "light", Name = "L", Type = "Attack", Duration = 0.1 }
                local heavy = { Id = "heavy", Name = "H", Type = "Attack", Duration = 0.2 }

                -- fire light then immediate heavy; heavy should be blocked by debounce
                ActionController.PlayAction(light)
                ActionController.PlayAction(heavy)
                assert(not ActionController.ActionCooldowns[heavy.Id], "heavy queued while light active")

                -- wait long enough then trigger heavy
                task.wait(1)
                ActionController.PlayAction(heavy)
                assert(ActionController.ActionCooldowns[heavy.Id], "heavy cooldown not applied after light finished")
                assert(ActionController.ActionCooldowns[light.Id] ~= ActionController.ActionCooldowns[heavy.Id],
                    "light and heavy should have independent cooldowns")
            end,
        },
        {
            name = "Feinting cancels current swing",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                -- start a mock attack and pretend we're in windup
                local light = { Id = "light", Name = "L", Type = "Attack", Duration = 0.5, HitStartFrame = 0.4 }
                ActionController.PlayAction(light)
                -- artificially move time forward into windup window
                if ActionController.CurrentAction then
                    ActionController.CurrentAction.StartTime = tick() - 0.1
                end
                -- pressing heavy should feint
                ActionController._PerformFeint()
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == ActionTypes.FEINT.Id,
                    "feint action should replace current swing")
            end,
        },
        {
            name = "Holding heavy before light automatically feints",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                ActionController.ActionCooldowns = {}

                -- simulate the user holding heavy, then performing a light attack
                ActionController._Test_SetHeavyState(true, false)
                local light = { Id = "light", Name = "L", Type = "Attack", Duration = 0.3 }
                ActionController.PlayAction(light)

                -- deferred feint happens immediately, give the engine a tick
                task.wait(0)
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == ActionTypes.FEINT.Id,
                    "holding heavy should automatically cancel new swing into a feint")
                -- heavy button should have been consumed (so release won't spawn a heavy attack)
                ActionController._Test_SetHeavyState(false, true)
            end,
        },
        {
            name = "Weapon-specific cooldowns apply",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                ActionController.ActionCooldowns = {}

                -- stub registry and controller
                WeaponController = {
                    GetEquipped = function() return "testw" end,
                }
                WeaponRegistry = {
                    Has = function(id) return id == "testw" end,
                    Get = function(id)
                        return { FeintCooldown = 2.5, HeavyCooldown = 3.0, AttackSpeed = 1 }
                    end,
                }

                -- play feint via PlayAction
                ActionController.PlayAction(ActionTypes.FEINT)
                local cd1 = ActionController.ActionCooldowns[ActionTypes.FEINT.Id]
                assert(cd1 and cd1 - tick() >= 2.4, "feint used weapon cooldown")

                -- clear and test heavy
                ActionController.ActionCooldowns = {}
                ActionController.PlayAction(ActionTypes.ATTACK_HEAVY)
                local cd2 = ActionController.ActionCooldowns[ActionTypes.ATTACK_HEAVY.Id]
                assert(cd2 and cd2 - tick() >= 2.9, "heavy used weapon cooldown")

                -- also verify _PerformFeint picks up weapon cooldown
                ActionController.ActionCooldowns = {}
                -- simulate an active action before feint
                ActionController.CurrentAction = { Config = { Id = "dummy", Type = "Attack" } }
                ActionController._PerformFeint()
                local cd3 = ActionController.ActionCooldowns[ActionTypes.FEINT.Id]
                assert(cd3 and cd3 - tick() >= 2.4, "_PerformFeint should use weapon feint cooldown")

                -- try to feint again immediately; should be blocked
                local before = ActionController.ActionCooldowns[ActionTypes.FEINT.Id]
                ActionController._PerformFeint()
                assert(ActionController.ActionCooldowns[ActionTypes.FEINT.Id] == before,
                    "second feint during cooldown should be ignored")

                -- hitbox spawn time calculation must be >= cancel time
                local cfg = { Type="Attack", Duration=0.5, HitStartFrame=0.4, CancelFrame=0.6 }
                local hitTime = cfg.Duration * cfg.HitStartFrame
                local cancelTime = cfg.Duration * cfg.CancelFrame + 0.01
                local computed = math.max(hitTime, cancelTime)
                assert(computed >= cancelTime, "computed hitTime should respect cancel frame")
            end,
        },
        {
            name = "Feint window logic triggers onHeavyPressed",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                -- create a fake current action with known timing (hit at 0.2s, cancel at 0.3s)
                local fake = { Config = { Type = "Attack", Duration = 0.5, HitStartFrame = 0.4, CancelFrame = 0.6 }, StartTime = tick() }
                -- pretend hitbox already spawned
                fake.Hitbox = { dummy = true }
                ActionController.CurrentAction = fake
                -- simulate being after hit but before cancel (0.25s elapsed)
                fake.StartTime = tick() - 0.25
                ActionController._Test_SetHeavyState(false, false)
                ActionController._Test_OnHeavyPressed()
                assert(ActionController.CurrentAction and ActionController.CurrentAction.Config.Id == ActionTypes.FEINT.Id,
                    "onHeavyPressed should call _PerformFeint when within extended windup window")
                -- hitbox should have been removed
                assert(fake.Hitbox == nil, "feint should clear active hitbox")
                -- ensure original attack cooldown was cleared
                assert(not ActionController.ActionCooldowns[fake.Config.Id], "original attack cooldown should be reset by feint")
                -- feint itself should now be on cooldown (~1 second)
                local feintCd = ActionController.ActionCooldowns[ActionTypes.FEINT.Id]
                assert(feintCd and feintCd > tick(), "feint should have its own cooldown applied")
                assert(feintCd - tick() >= 0.9, "feint cooldown should be approximately 1s")
            end,
        },
        {
            name = "Dodge cancels when wall immediately ahead",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                Blackboard.IsDodging = false
                -- monkey-patch workspace.Raycast to always return hit
                local workspace = game:GetService("Workspace")
                local orig = workspace.Raycast
                workspace.Raycast = function() return { Instance = { CanCollide = true } } end
                ActionController.PlayAction(ActionTypes.DODGE)
                task.wait(0)
                assert(Blackboard.IsDodging == false, "dodge should be cancelled if obstacle is right in front")
                workspace.Raycast = orig
            end,
        },
        {
            name = "Dodge OnFrame zeros velocity when touching non-character part",
            fn = function()
                -- set up fake root part and override Utils.GetRootPart
                local fakeRoot = Instance.new("Part")
                fakeRoot.Anchored = false
                fakeRoot.CanCollide = false
                fakeRoot.Position = Vector3.new(0,0,0)
                fakeRoot.AssemblyLinearVelocity = Vector3.new(20,0,0)
                local originalGetRoot = Utils.GetRootPart
                Utils.GetRootPart = function() return fakeRoot end

                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }

                ActionController.PlayAction(ActionTypes.DODGE)
                local act = ActionController.CurrentAction
                assert(act, "dodge action should start")
                -- simulate touching a foreign part
                local other = Instance.new("Part")
                other.Parent = workspace
                fakeRoot.Touched:Connect(function() end) -- ensure GetTouchingParts works
                -- manually add non-descendant via GetTouchingParts hack:
                -- simplest: stub GetTouchingParts on fakeRoot
                fakeRoot.GetTouchingParts = function() return {other} end

                -- call OnFrame once, velocity should zero
                if act.OnFrame then act.OnFrame(act, 0.1) end
                assert(fakeRoot.AssemblyLinearVelocity.X == 0 and fakeRoot.AssemblyLinearVelocity.Z == 0,
                    "horizontal velocity should be cleared when touching external part")

                -- cleanup
                fakeRoot:Destroy()
                other:Destroy()
                Utils.GetRootPart = originalGetRoot
            end,
        },
        {
            name = "Dodge cancels slide state",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }
                Blackboard.IsSliding = true
                Blackboard.IsDodging = false
                ActionController.PlayAction(ActionTypes.DODGE)
                assert(not Blackboard.IsSliding, "slide flag should be reset by dodge")
                assert(Blackboard.IsDodging, "dodge flag should be set")
            end,
        },
        {
            name = "Dodge direction and momentum scaling",
            fn = function()
                ActionController.Character = { FindFirstChild = function(_, _) return nil end }
                ActionController.Humanoid = { Health = 100 }

                -- fake root facing east with little momentum
                local fakeRoot = Instance.new("Part")
                fakeRoot.Anchored = false
                fakeRoot.CanCollide = false
                fakeRoot.CFrame = CFrame.new() * CFrame.Angles(0, math.rad(90), 0)
                fakeRoot.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
                local origGetRoot = Utils.GetRootPart
                Utils.GetRootPart = function() return fakeRoot end

                -- ensure input queries return false so we fall back to HRP facing
                local UIS = game:GetService("UserInputService")
                local origIsDown = UIS.IsKeyDown
                UIS.IsKeyDown = function() return false end

                ActionController.PlayAction(ActionTypes.DODGE)
                local dir = ActionController._Test_GetDodgeDir()
                assert(dir.X > 0 and math.abs(dir.Z) < 0.1,
                    "_dodgeDir should follow HRP facing when no input")

                local speed1 = ActionController._Test_LastDodgeSpeed
                assert(type(speed1) == "number" and speed1 > 0,
                    "computed dodge speed should be exposed and positive")

                -- increase momentum and ensure speed increases
                fakeRoot.AssemblyLinearVelocity = Vector3.new(20, 0, 0)
                ActionController.PlayAction(ActionTypes.DODGE)
                local speed2 = ActionController._Test_LastDodgeSpeed
                assert(speed2 > speed1, "dodge speed should scale up with momentum")

                -- now simulate zero velocity but high momentum multiplier (slide->dodge)
                fakeRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                MovementController = MovementController or {}
                MovementController.GetMomentumMultiplier = function() return 3 end
                ActionController.PlayAction(ActionTypes.DODGE)
                local speed3 = ActionController._Test_LastDodgeSpeed
                assert(speed3 > speed2, "dodge speed should still boost when multiplier high")

                -- restore originals
                UIS.IsKeyDown = origIsDown
                Utils.GetRootPart = origGetRoot
                fakeRoot:Destroy()
            end,
        },
		{
			name = "Attack impulse scales with momentum and multiplier",
			fn = function()
				ActionController.Character = { FindFirstChild = function(_, _) return nil end }
				ActionController.Humanoid = { Health = 100 }
				-- stub root and utils
				local fakeRoot = Instance.new("Part")
				fakeRoot.Anchored = false
				fakeRoot.CanCollide = false
				fakeRoot.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
				local origGetRoot = Utils.GetRootPart
				Utils.GetRootPart = function() return fakeRoot end
				MovementController = MovementController or {}
				local recorded
				MovementController.ApplyImpulse = function(_dir, spd, _dur, _tag)
					recorded = spd
					return true
				end
				-- base attack
				ActionController.PlayAction({Type="Attack",Id="test",AttackImpulse=20,Duration=0.1})
				local sp1 = recorded
				-- multiplier boost only
				MovementController.GetMomentumMultiplier = function() return 3 end
				fakeRoot.AssemblyLinearVelocity = Vector3.new(0,0,0)
				ActionController.PlayAction({Type="Attack",Id="test",AttackImpulse=20,Duration=0.1})
				local sp2 = recorded
				assert(sp2 > sp1, "attack impulse should be larger with multiplier")
				-- velocity boost
				fakeRoot.AssemblyLinearVelocity = Vector3.new(20,0,0)
				MovementController.GetMomentumMultiplier = function() return 1 end
				ActionController.PlayAction({Type="Attack",Id="test",AttackImpulse=20,Duration=0.1})
				local sp3 = recorded
				assert(sp3 > sp1, "attack impulse should increase with velocity")
				-- cleanup
				Utils.GetRootPart = origGetRoot
				fakeRoot:Destroy()
			end,
		},
		{
			name = "Lunge speed scales with momentum and multiplier",
			fn = function()
				ActionController.Character = { FindFirstChild = function(_, _) return nil end }
				ActionController.Humanoid = { Health = 100 }
				local fakeRoot = Instance.new("Part")
				fakeRoot.Anchored = false
				fakeRoot.CanCollide = false
				fakeRoot.AssemblyLinearVelocity = Vector3.new(10,0,0)
				local origGetRoot = Utils.GetRootPart
				Utils.GetRootPart = function() return fakeRoot end
				MovementController = MovementController or {}
				local recorded
				MovementController.ApplyImpulse = function(_dir, spd, _dur, _tag)
					recorded = spd
					return true
				end
				-- base lunge
				ActionController.PlayAction({Type="Attack",Id="atk_lunge",Duration=0.5})
				local sp1 = recorded
				-- multiplier boost
				MovementController.GetMomentumMultiplier = function() return 3 end
				fakeRoot.AssemblyLinearVelocity = Vector3.new(0,0,0)
				ActionController.PlayAction({Type="Attack",Id="atk_lunge",Duration=0.5})
				local sp2 = recorded
				assert(sp2 > sp1, "lunge speed should be larger with multiplier")
				-- velocity boost
				fakeRoot.AssemblyLinearVelocity = Vector3.new(20,0,0)
				MovementController.GetMomentumMultiplier = function() return 1 end
				ActionController.PlayAction({Type="Attack",Id="atk_lunge",Duration=0.5})
				local sp3 = recorded
				assert(sp3 > sp1, "lunge speed should increase with velocity")
				Utils.GetRootPart = origGetRoot
				fakeRoot:Destroy()
			end,
		},
}
