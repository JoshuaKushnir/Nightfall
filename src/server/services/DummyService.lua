--!strict
--[[
DummyService.lua

Manages combat test dummies for development.
Provides spawn/despawn functionality and dummy state management.

States:
  Normal    - default; takes full damage
  Blocking  - takes 50% damage; cycles automatically every ~8s for 3s
  Staggered - entered after any hit; lasts 1.5s then reverts to Normal

Issue #64: Spawnable test dummies for attack testing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DummyDataModule = require(ReplicatedStorage.Shared.types.DummyData)
type DummyData  = DummyDataModule.DummyData
type DummyState = DummyDataModule.DummyState

local Utils           = require(ReplicatedStorage.Shared.modules.Utils)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local Loader          = require(ReplicatedStorage.Shared.modules.Loader)

local DummyService = {}

-- Storage
local ActiveDummies: {[string]: DummyData} = {}
local DummyModels:   {[string]: Model}     = {}

-- Constants
local DUMMY_HEALTH       = 100
local DUMMY_POSTURE      = 80
local DUMMY_LIFETIME     = 300  -- 5 minutes auto-despawn
local STAGGER_DURATION   = 1.5  -- seconds spent in Staggered
local BLOCK_INTERVAL_MIN = 6    -- seconds between block windows
local BLOCK_INTERVAL_MAX = 10
local BLOCK_DURATION     = 3    -- seconds a dummy holds a block
local BLOCK_DAMAGE_MULT  = 0.5  -- 50% damage while blocking

local SPAWN_EVENT_NAME         = "SpawnDummy"
local DESPAWN_EVENT_NAME       = "DespawnDummy"
local STATE_CHANGED_EVENT_NAME = "DummyStateChanged"

-- Per-state tint applied to all body parts
local STATE_COLORS: {[DummyState]: BrickColor} = {
Normal    = BrickColor.new("Medium stone grey"),
Blocking  = BrickColor.new("Bright blue"),
Staggered = BrickColor.new("Bright orange"),
}

-- Default positions where dummies auto-spawn on game start
local AUTO_SPAWN_POSITIONS: {Vector3} = {
Vector3.new(0,  3,  10),
Vector3.new(10, 3,  0),
Vector3.new(-10, 3, 0),
}

-- ──────────────────────────────────────────────────────────────────────────
-- Init / Start
-- ──────────────────────────────────────────────────────────────────────────

function DummyService:Init()
print("[DummyService] Initializing...")
game:BindToClose(function()
DummyService._CleanupAllDummies()
end)
print("[DummyService] Initialized successfully")
end

function DummyService:Start()
print("[DummyService] Starting...")

for _, pos in AUTO_SPAWN_POSITIONS do
DummyService.SpawnDummy(pos)
end
print(`[DummyService] Auto-spawned {#AUTO_SPAWN_POSITIONS} dummy(s) at game start`)

local spawnEvent = NetworkProvider:GetRemoteEvent(SPAWN_EVENT_NAME)
if spawnEvent then
spawnEvent.OnServerEvent:Connect(function(player, position)
if not DummyService._IsPlayerAllowed(player) then
warn(`[DummyService] Spawn denied for {player.Name} - dev-only`)
return
end
DummyService.SpawnDummy(position)
end)
end

local despawnEvent = NetworkProvider:GetRemoteEvent(DESPAWN_EVENT_NAME)
if despawnEvent then
despawnEvent.OnServerEvent:Connect(function(player, dummyId)
if not DummyService._IsPlayerAllowed(player) then
warn(`[DummyService] Despawn denied for {player.Name} - dev-only`)
return
end
DummyService.DespawnDummy(dummyId)
end)
end

print("[DummyService] Started successfully")
end

-- ──────────────────────────────────────────────────────────────────────────
-- Permission check
-- ──────────────────────────────────────────────────────────────────────────

function DummyService._IsPlayerAllowed(player: Player?): boolean
if Loader and Loader.IsStudio and Loader.IsStudio() then
return true
end
if player and player.UserId == game.CreatorId then
return true
end
return false
end

-- ──────────────────────────────────────────────────────────────────────────
-- Model construction
-- ──────────────────────────────────────────────────────────────────────────

--[[
Build an R6-compatible humanoid rig for the dummy.
Parts: HumanoidRootPart (invisible anchor), Torso, Head, 4 limbs, Humanoid.
A BillboardGui above the head labels the current state.
]]
function DummyService._CreateDummyModel(dummyData: DummyData): Model?
local model = Instance.new("Model")
model.Name = `Dummy_{dummyData.Id}`

local color = STATE_COLORS[dummyData.State]

local function makePart(name: string, size: Vector3, offset: Vector3): Part
local p = Instance.new("Part")
p.Name       = name
p.Size       = size
p.CFrame     = CFrame.new(dummyData.Position + offset)
p.Anchored   = true
p.CanCollide = true
p.BrickColor = color
p.Material   = Enum.Material.SmoothPlastic
p.Parent     = model
return p
end

-- Invisible root (collision-free anchor / hitbox origin)
local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
root.Transparency = 1
root.CanCollide   = false

-- Body parts
makePart("Torso",      Vector3.new(2, 2, 1), Vector3.new(0,    1,    0))
local head = makePart("Head", Vector3.new(1, 1, 1), Vector3.new(0,    2.5,  0))
makePart("Left Arm",   Vector3.new(1, 2, 1), Vector3.new(-1.5, 1,    0))
makePart("Right Arm",  Vector3.new(1, 2, 1), Vector3.new( 1.5, 1,    0))
makePart("Left Leg",   Vector3.new(1, 2, 1), Vector3.new(-0.5, -1,   0))
makePart("Right Leg",  Vector3.new(1, 2, 1), Vector3.new( 0.5, -1,   0))

-- Humanoid (health bar + detection compatibility)
local humanoid = Instance.new("Humanoid")
humanoid.DisplayName = "Dummy"
humanoid.Health      = dummyData.Health
humanoid.MaxHealth   = dummyData.MaxHealth
humanoid.WalkSpeed   = 0
humanoid.JumpPower   = 0
humanoid.Parent      = model

model.PrimaryPart = root

-- BillboardGui: state label above the head
local billboard = Instance.new("BillboardGui")
billboard.Name        = "StateLabel"
billboard.Size        = UDim2.new(4, 0, 1, 0)
billboard.StudsOffset = Vector3.new(0, 1.5, 0)
billboard.AlwaysOnTop = false
billboard.Adornee     = head
billboard.Parent      = head

local label = Instance.new("TextLabel")
label.Name                   = "Label"
label.Size                   = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.TextColor3             = Color3.new(1, 1, 1)
label.TextScaled             = true
label.Font                   = Enum.Font.GothamBold
label.Text                   = dummyData.State
label.Parent                 = billboard

model.Parent = Workspace
return model
end

-- ──────────────────────────────────────────────────────────────────────────
-- State management
-- ──────────────────────────────────────────────────────────────────────────

--[[
Refresh body-part colors, the billboard label, and the Humanoid health bar.
]]
function DummyService._UpdateVisuals(dummyId: string)
local dummyData = ActiveDummies[dummyId]
local model     = DummyModels[dummyId]
if not dummyData or not model then return end

local color = STATE_COLORS[dummyData.State]
for _, part in model:GetDescendants() do
if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
(part :: BasePart).BrickColor = color
end
end

local head: BasePart? = model:FindFirstChild("Head") :: BasePart?
if head then
local bb  = head:FindFirstChild("StateLabel") :: BillboardGui?
local lbl = bb and bb:FindFirstChild("Label") :: TextLabel?
if lbl then lbl.Text = dummyData.State end
end

local humanoid = model:FindFirstChildOfClass("Humanoid")
if humanoid then
humanoid.Health    = dummyData.Health
humanoid.MaxHealth = dummyData.MaxHealth
end
end

--[[
Change a dummy's state, update visuals, and broadcast to clients.
Staggered auto-recovers to Normal after STAGGER_DURATION seconds.
]]
function DummyService.SetDummyState(dummyId: string, state: DummyState)
local dummyData = ActiveDummies[dummyId]
if not dummyData or not dummyData.IsActive then return end

dummyData.State = state
DummyService._UpdateVisuals(dummyId)

print(`[DummyService] Dummy {dummyId} state -> {state}`)

local evt = NetworkProvider:GetRemoteEvent(STATE_CHANGED_EVENT_NAME)
if evt then
evt:FireAllClients({
DummyId   = dummyId,
State     = state,
Health    = dummyData.Health,
MaxHealth = dummyData.MaxHealth,
})
end

-- Auto-recover from Stagger
if state == "Staggered" then
task.delay(STAGGER_DURATION, function()
local d = ActiveDummies[dummyId]
if d and d.State == "Staggered" then
DummyService.SetDummyState(dummyId, "Normal")
end
end)
end
end

--[[
Get the current DummyState for a dummy.
]]
function DummyService.GetDummyState(dummyId: string): DummyState?
local d = ActiveDummies[dummyId]
return d and d.State or nil
end

--[[
Get the Model instance for a dummy (used by CombatService/AbilitySystem).
]]
function DummyService.GetDummyModel(dummyId: string): Model?
return DummyModels[dummyId]
end

--[[
Periodic blocking cycle: every BLOCK_INTERVAL seconds the dummy enters
Blocking for BLOCK_DURATION seconds, then returns to Normal.
Only runs while the dummy is alive.
]]
function DummyService._StartBlockingCycle(dummyId: string)
task.spawn(function()
while ActiveDummies[dummyId] do
local interval = math.random(BLOCK_INTERVAL_MIN, BLOCK_INTERVAL_MAX)
task.wait(interval)

if not ActiveDummies[dummyId] then break end

-- Only enter block from Normal to not interrupt Stagger
if ActiveDummies[dummyId].State == "Normal" then
DummyService.SetDummyState(dummyId, "Blocking")
task.wait(BLOCK_DURATION)
local d = ActiveDummies[dummyId]
if d and d.State == "Blocking" then
DummyService.SetDummyState(dummyId, "Normal")
end
end
end
end)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Public spawn/despawn API
-- ──────────────────────────────────────────────────────────────────────────

--[[
Spawn a dummy at position.
@return Dummy ID, or nil on failure.
]]
function DummyService.SpawnDummy(position: Vector3): string?
local dummyId = Utils.GenerateId()

local dummyData: DummyData = {
Id         = dummyId,
Position   = position,
Health     = DUMMY_HEALTH,
MaxHealth  = DUMMY_HEALTH,
Posture    = DUMMY_POSTURE,
MaxPosture = DUMMY_POSTURE,
State      = "Normal",
IsActive   = true,
SpawnTime  = tick(),
}

local model = DummyService._CreateDummyModel(dummyData)
if not model then
warn("[DummyService] Failed to create dummy model")
return nil
end

ActiveDummies[dummyId] = dummyData
DummyModels[dummyId]   = model

task.delay(DUMMY_LIFETIME, function()
if ActiveDummies[dummyId] then
DummyService.DespawnDummy(dummyId)
end
end)

DummyService._StartBlockingCycle(dummyId)

print(`[DummyService] Dummy spawned: {dummyId} at {position}`)

local spawnEvent = NetworkProvider:GetRemoteEvent(SPAWN_EVENT_NAME)
if spawnEvent then spawnEvent:FireAllClients(dummyData) end

return dummyId
end

--[[
Remove a dummy from the world.
]]
function DummyService.DespawnDummy(dummyId: string)
local dummyData = ActiveDummies[dummyId]
if not dummyData then
print(`[DummyService] Dummy not found: {dummyId}`)
return
end

dummyData.IsActive = false

local model = DummyModels[dummyId]
if model then
model:Destroy()
DummyModels[dummyId] = nil
end

ActiveDummies[dummyId] = nil
print(`[DummyService] Dummy despawned: {dummyId}`)

local despawnEvent = NetworkProvider:GetRemoteEvent(DESPAWN_EVENT_NAME)
if despawnEvent then despawnEvent:FireAllClients(dummyId) end
end

--[[
Apply damage to a dummy.
Blocking halves incoming damage.
Any surviving hit transitions the dummy to Staggered.
@return true if dummy is still alive
]]
function DummyService.ApplyDamage(dummyId: string, damage: number): boolean
local dummyData = ActiveDummies[dummyId]
if not dummyData or not dummyData.IsActive then return false end

-- Blocking reduces damage
local effectiveDamage = damage
if dummyData.State == "Blocking" then
effectiveDamage = math.floor(damage * BLOCK_DAMAGE_MULT)
print(`[DummyService] Dummy {dummyId} blocked: {damage} -> {effectiveDamage}`)
end

dummyData.Health = math.max(0, dummyData.Health - effectiveDamage)

-- Sync Humanoid health (drives the in-world health bar)
local model = DummyModels[dummyId]
if model then
local humanoid = model:FindFirstChildOfClass("Humanoid")
if humanoid then humanoid.Health = dummyData.Health end
DummyService._UpdateVisuals(dummyId)
end

if dummyData.Health <= 0 then
print(`[DummyService] Dummy defeated: {dummyId}`)
DummyService.DespawnDummy(dummyId)
return false
end

print(`[DummyService] Dummy hit: {dummyId} ({effectiveDamage} dmg, {dummyData.Health}/{dummyData.MaxHealth} HP)`)

-- Stagger on any non-staggered hit
if dummyData.State ~= "Staggered" then
DummyService.SetDummyState(dummyId, "Staggered")
end

return true
end

--[[
Return data for a dummy by ID.
]]
function DummyService.GetDummyData(dummyId: string): DummyData?
return ActiveDummies[dummyId]
end

--[[
Return all active dummy datasets.
]]
function DummyService.GetAllDummies(): {DummyData}
local out = {}
for _, d in ActiveDummies do table.insert(out, d) end
return out
end

-- ──────────────────────────────────────────────────────────────────────────
-- Cleanup
-- ──────────────────────────────────────────────────────────────────────────

function DummyService._CleanupAllDummies()
for dummyId in ActiveDummies do
DummyService.DespawnDummy(dummyId)
end
end

return DummyService
