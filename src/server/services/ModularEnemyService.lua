--!strict
--[[
    Class: ModularEnemyService
    Description: AAA Data-driven AI core using Behavior Trees and decoupled movesets.
    Dependencies: HitboxService, StateService, NetworkProvider, DummyService
    Usage: Required by Server to manage all modular enemies.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyTypes = require(Shared.types.EnemyTypes)
local AnimationDatabase = require(Shared.AnimationDatabase)
local HitboxService = require(Shared.modules.HitboxService)
local NetworkProvider = require(Shared.network.NetworkProvider)

local SpawnerConfig = require(game:GetService("ServerScriptService").Server.modules.SpawnerConfig)

local DummyService: any = nil
local PostureService: any = nil
local ProgressionService: any = nil

local MovesetsFolder = script.Parent.Parent:WaitForChild("modules"):WaitForChild("movesets")

type EnemyData = EnemyTypes.EnemyData
type EnemyMoveset = EnemyTypes.EnemyMoveset

local ModularEnemyService = {}
ModularEnemyService._initialized = false

local _enemies: {[string]: EnemyData} = {}
local _ext: {[string]: any} = {} -- Extended combat state (cooldowns, threat, etc.)
local _models: {[string]: Model} = {}
local _nextId = 0
local _tickConn: RBXScriptConnection?

local _instanceAreaMap: {[string]: string} = {}
local _spawnerConfig: SpawnerConfig.SpawnerConfig = SpawnerConfig.GetDefaultConfig()
local _lastSpawnCheckTime: number = 0

-- ─── Helper Functions ────────────────────────────────────────────────────────

local function FindNearestPlayer(pos: Vector3, range: number): BasePart?
    local nearest: BasePart? = nil
    local minDist = range
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and player.Character.PrimaryPart then
            local root = player.Character.PrimaryPart
            local dist = (root.Position - pos).Magnitude
            if dist <= minDist then
                minDist = dist
                nearest = root
            end
        end
    end
    return nearest
end

local function LoadModel(configId: string): Model
    -- Fallback to a basic rig for now since ReplicatedStorage.Models might not be populated yet
    local model = Instance.new("Model")
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(2, 2, 1)
    root.Transparency = 1
    root.Parent = model
    model.PrimaryPart = root

    local humanoid = Instance.new("Humanoid")
    humanoid.Parent = model

    return model
end

-- ─── Behavior Tree Nodes ─────────────────────────────────────────────────────

local BT_Nodes = {
    -- 1. Reactions (Parry / Dodge)
    function(data: EnemyData, target: BasePart, now: number): boolean
        if data.State == "Dead" or data.State == "Staggered" then return true end
        local ex = _ext[data.InstanceId]

        -- Pseudo-reaction check (simplified for now)
        if ex.IncomingHitPredicted then
            if data.Moveset.Personality.Caution > 0.5 and (now - ex.LastDodge > 3) then
                data.State = "Dodging"
                ex.LastDodge = now
                -- Dodge Logic here
                return true
            end
        end
        return false
    end,

    -- 2. Attack
    function(data: EnemyData, target: BasePart, now: number): boolean
        local ex = _ext[data.InstanceId]
        if data.State ~= "Combat" and data.State ~= "Alert" then return false end
        if now - ex.LastAttack < 2.0 then return false end -- Cooldown

        local dist = (target.Position - data.Model.PrimaryPart.Position).Magnitude
        local candidates = {}

        for name, move in pairs(data.Moveset.Attacks) do
            if move.Range and move.Range >= dist then
                table.insert(candidates, {Name = name, Move = move, Weight = move.Weight or 1})
            end
        end

        if #candidates > 0 then
            -- Weighted random pick (simplified to first for skeleton)
            local chosen = candidates[1].Move
            data.State = "Attacking"
            ex.LastAttack = now

            -- Attack Logic here (Animations, Hitboxes)
            -- HitboxService.SpawnHitbox(...)
            return true
        end

        return false
    end,

    -- 3. Movement / Spacing
    function(data: EnemyData, target: BasePart, now: number): boolean
        local root = data.Model.PrimaryPart
        local dist = (target.Position - root.Position).Magnitude
        local humanoid = data.Model:FindFirstChild("Humanoid") :: Humanoid

        if humanoid then
            if dist > data.Moveset.Stats.AggroRange then
                data.State = "Patrol"
            else
                data.State = "Combat"
                -- Move towards target (simplified)
                if dist > 5 then
                    humanoid:MoveTo(target.Position)
                else
                    humanoid:MoveTo(root.Position) -- Stop moving
                end
            end
        end
        return true
    end
}

-- ─── Main Tick ───────────────────────────────────────────────────────────────

local function _CountInArea(area: string): number
    local n = 0
    for id, a in pairs(_instanceAreaMap) do
        if a == area and _enemies[id] and _enemies[id].State ~= "Dead" then n += 1 end
    end
    return n
end

local function _TrySpawnRespawns()
    local variants = {"basic_hollowed"} -- Add more variants as movesets are created
    for _, zone in ipairs(_spawnerConfig.SpawnZones) do
        local cur = _CountInArea(zone.AreaName)
        if cur < zone.MobCap and math.random() < 0.3 then
            local pos = SpawnerConfig.FindSafeSpawnPosition(zone, _enemies,
                _spawnerConfig.CollisionCheckRadius, _spawnerConfig.MinSpawnDistance, 5)
            if pos then
                local v  = variants[math.random(1, #variants)]
                local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(math.random(0,360)), 0)
                local id = ModularEnemyService.SpawnInstance(v, cf)
                if id then
                    _instanceAreaMap[id] = zone.AreaName
                end
            end
        end
    end
end

local function OnTick(dt: number)
    local now = tick()

    if now - _lastSpawnCheckTime >= _spawnerConfig.RespawnCheckInterval then
        _lastSpawnCheckTime = now
        _TrySpawnRespawns()
    end

    for id, data in pairs(_enemies) do
        if data.State == "Dead" then continue end
        local root = data.Model.PrimaryPart
        if not root then continue end

        local target = FindNearestPlayer(root.Position, data.Moveset.Stats.AggroRange)
        if not target then
            data.State = "Patrol"
            -- UpdatePatrol(data)
            continue
        end

        -- Run Behavior Tree
        for _, node in ipairs(BT_Nodes) do
            if node(data, target, now) then
                break
            end
        end
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function ModularEnemyService.SpawnInstance(configId: string, spawnCF: CFrame): string?
    local movesetModule = MovesetsFolder:FindFirstChild(configId)
    if not movesetModule then
        warn(("[ModularEnemyService] No Moveset found for: %s"):format(configId))
        return nil
    end

    local moveset: EnemyMoveset = require(movesetModule) :: any

    _nextId += 1
    local instanceId = ("Enemy_%s_%d"):format(configId, _nextId)

    local model = LoadModel(configId)
    model.Name = instanceId
    model:PivotTo(spawnCF)
    model.Parent = Workspace
    _models[instanceId] = model

    local data: EnemyData = {
        InstanceId = instanceId,
        ConfigId = configId,
        Model = model,
        Moveset = moveset,
        State = "Patrol",
        CurrentHealth = moveset.Stats.MaxHealth,
        CurrentPoise = moveset.Stats.MaxPoise,
        SpawnPosition = spawnCF.Position,
    }

    _enemies[instanceId] = data
    _ext[instanceId] = {
        LastAttack = 0,
        LastDodge = 0,
        LastParry = 0,
        IncomingHitPredicted = false,
    }

    return instanceId
end

function ModularEnemyService.DespawnInstance(instanceId: string)
    local model = _models[instanceId]
    if model then
        model:Destroy()
        _models[instanceId] = nil
    end
    _enemies[instanceId] = nil
    _ext[instanceId] = nil
    _instanceAreaMap[instanceId] = nil
end

function ModularEnemyService.ApplyDamage(instanceId: string, damage: number, attacker: Player?, postureDamage: number?): boolean
    local data = _enemies[instanceId]
    if not data or data.State == "Dead" or data.State == "Dodging" then return false end

    data.CurrentHealth -= damage
    if postureDamage then
        data.CurrentPoise -= postureDamage
    end

    if data.CurrentHealth <= 0 then
        data.State = "Dead"
        -- Handle death (drops, resonance, cleanup)
        if attacker and ProgressionService then
            ProgressionService.GrantResonance(attacker, data.Moveset.Stats.ResonanceGrant, "Hollowed")
        end
        task.delay(data.Moveset.Stats.RespawnDelay, function()
            ModularEnemyService.DespawnInstance(instanceId)
        end)
        return false
    end

    return true
end

function ModularEnemyService.GetInstanceData(instanceId: string): EnemyData?
    return _enemies[instanceId]
end

function ModularEnemyService.GetAllInstances(): {[string]: EnemyData}
    return _enemies
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function ModularEnemyService.SetSpawnerConfig(cfg: SpawnerConfig.SpawnerConfig)
    _spawnerConfig = cfg
end

function ModularEnemyService:Init(dependencies: {[string]: any}?)
    if dependencies then
        DummyService = dependencies.DummyService
        PostureService = dependencies.PostureService
        ProgressionService = dependencies.ProgressionService
    end
    ModularEnemyService._initialized = true
    print("[ModularEnemyService] Initialized")
end

function ModularEnemyService:Start()
    assert(ModularEnemyService._initialized, "Call Init() first")
    _tickConn = RunService.Heartbeat:Connect(OnTick)
    print("[ModularEnemyService] Started tick loop")
end

function ModularEnemyService:Shutdown()
    if _tickConn then
        _tickConn:Disconnect()
        _tickConn = nil
    end
    for id in pairs(_enemies) do
        ModularEnemyService.DespawnInstance(id)
    end
end

return ModularEnemyService
