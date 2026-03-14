--!strict
--[[
    Class: DeathService
    Description: Handles the server-side death-and-respawn flow.
                 When a player enters the "Dead" state, DeathService waits for
                 the client death screen to complete (configurable RESPAWN_DELAY),
                 resets player data, calls LoadCharacter, and fires PlayerRespawned
                 to the client.

                 Ember Points: respawn location uses the nearest registered Ember
                 Point if any exist in Workspace.EmberPoints; otherwise falls back
                 to the default character spawn. EmberPoint instances are tagged
                 "EmberPoint" and must be Part or Model with a "Spawn" attachment
                 or a CFrame attribute named "SpawnCFrame".

    Dependencies: NetworkService, DataService, StateService, CombatService (lazy)
    Issue: #144 — Death respawn flow
]]

local Players      = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")

local NetworkService  = require(ReplicatedStorage.Shared.network.NetworkProvider)
local StateService    = require(ReplicatedStorage.Shared.modules.StateService)
local Utils           = require(ReplicatedStorage.Shared.modules.Utils)

-- Lazy-require to avoid circular deps
local _DataService: any    = nil
local _CombatService: any  = nil

local function _requireDataService()
    if not _DataService then
        _DataService = require(ServerScriptService.Server.services.DataService)
    end
    return _DataService
end

local function _requireCombatService()
    if not _CombatService then
        _CombatService = require(ServerScriptService.Server.services.CombatService)
    end
    return _CombatService
end

-- ─── Constants ────────────────────────────────────────────────────────────────

-- Must match the death screen duration in CombatFeedbackUI:
--   1 s fade-in  +  2.5 s hold  +  0.5 s fade-out  = 4 s
local RESPAWN_DELAY: number = 4.0

-- Ember Point tag used by CollectionService
local EMBER_POINT_TAG = "EmberPoint"

-- Guard: prevent re-triggering respawn while one is already in progress
local _pendingRespawn: {[Player]: boolean} = {}

-- ─── Private helpers ──────────────────────────────────────────────────────────

--[[
    _findActiveEmberPoint(player, originCFrame)
    Returns the CFrame of the active player EmberPoint. If none, falls back to nearest tagged EmberPoint, or nil if none exist.
]]
local function _findActiveEmberPoint(player: Player, origin: CFrame?): CFrame?
    local profile = _requireDataService():GetProfile(player)
    if profile and profile.ActiveEmberPointId then
        local ptData = profile.EmberPoints and profile.EmberPoints[profile.ActiveEmberPointId]
        if ptData and ptData.Position then
            return CFrame.new(ptData.Position.X, ptData.Position.Y, ptData.Position.Z)
        end
    end

    if not origin then return nil end

    local best: CFrame? = nil
    local bestDist = math.huge

    for _, obj in CollectionService:GetTagged(EMBER_POINT_TAG) do
        local cf: CFrame?

        -- CFrame attribute takes priority
        local attr = obj:GetAttribute("SpawnCFrame")
        if typeof(attr) == "CFrame" then
            cf = attr
        elseif obj:IsA("BasePart") then
            cf = obj.CFrame
        elseif obj:IsA("Model") and obj.PrimaryPart then
            cf = obj.PrimaryPart.CFrame
        else
            -- Try named attachment
            local attach = obj:FindFirstChild("Spawn")
            if attach and attach:IsA("Attachment") then
                local parent = attach.Parent
                if parent and parent:IsA("BasePart") then
                    cf = parent.CFrame * attach.CFrame
                end
            end
        end

        if cf then
            local dist = (cf.Position - origin.Position).Magnitude
            if dist < bestDist then
                bestDist = dist
                best = cf
            end
        end
    end

    return best
end

--[[
    _respawnPlayer(player)
    Core respawn routine. Resets profile, LoadCharacter, force-idles state.
]]
local function _respawnPlayer(player: Player)
    if not Utils.IsValidPlayer(player) then
        _pendingRespawn[player] = nil
        return
    end

    -- 1. Restore health in profile so the spawned character has full HP
    local profile = _requireDataService():GetProfile(player)
    if profile then
        profile.Health.Current = profile.Health.Max
        -- Posture also resets on respawn
        profile.Posture.Current = 0
    end

    -- 2. Determine spawn CFrame (Ember Point or default)
    local spawnCFrame: CFrame? = nil
    local char = player.Character
    if char and char.PrimaryPart then
        spawnCFrame = _findActiveEmberPoint(player, char.PrimaryPart.CFrame)
    else
        spawnCFrame = _findActiveEmberPoint(player, nil)
    end

    -- 3a. Immediately reset state back to Idle before the character appears
    --     this prevents any invalid transitions if the client sends input while
    --     the new avatar is still loading.
    StateService:SetPlayerState(player, "Idle", true)

    -- 3. Respawn
    player:LoadCharacter()

    -- 3b. Also watch for the character being added; some systems may fire
    --     actions on CharacterAdded itself so we set it again as a safety.
    player.CharacterAdded:Connect(function(newChar)
        StateService:SetPlayerState(player, "Idle", true)
    end)

    -- 4. Wait for new character to load, then set spawn CFrame + idle state
    local newChar = player.CharacterAdded:Wait()
    local humanoid = newChar:WaitForChild("Humanoid", 10) :: Humanoid?

    -- Position at Ember Point if found
    if spawnCFrame and newChar.PrimaryPart then
        -- Offset slightly upward so character doesn't clip into the floor
        newChar:SetPrimaryPartCFrame(spawnCFrame + Vector3.new(0, 3, 0))
    end

    -- 5. Reset state to Idle again to cover any race conditions
    StateService:SetPlayerState(player, "Idle", true)

    -- 6. Reset combat cooldowns so the player doesn't come back with locked abilities
    local cs = _requireCombatService()
    if cs and cs.ResetCooldowns then
        cs.ResetCooldowns(player)
    end

    -- 7. Sync health with Humanoid (profile is source of truth)
    if humanoid and profile then
        humanoid.MaxHealth = profile.Health.Max
        humanoid.Health    = profile.Health.Max
    end

    -- 8. Notify client
    NetworkService:SendToClient(player, "PlayerRespawned", {
        SpawnPosition = spawnCFrame and spawnCFrame.Position or nil,
    })

    print("[DeathService] " .. player.Name .. " respawned")
    _pendingRespawn[player] = nil
end

--[[
    _onStateChanged(player, oldState, newState)
    Called by StateChangedSignal. Triggers respawn pipeline on Dead transition.
]]
local function _onStateChanged(player: Player, _oldState: string, newState: string)
    if newState ~= "Dead" then return end
    if _pendingRespawn[player] then return end  -- already handling

    _pendingRespawn[player] = true

    print("[DeathService] " .. player.Name .. " died — respawning in " .. RESPAWN_DELAY .. "s")

    task.delay(RESPAWN_DELAY, function()
        _respawnPlayer(player)
    end)
end

-- ─── Service interface ────────────────────────────────────────────────────────

local DeathService = {}

function DeathService:Init(_dependencies: {[string]: any})
    -- nothing to pre-cache; all deps are lazy or module-level
end

function DeathService:Start()
    -- Listen for Dead state transitions
    local signal = StateService:GetStateChangedSignal()
    signal:Connect(_onStateChanged)

    -- Clean up pending guard if player leaves mid-death
    Players.PlayerRemoving:Connect(function(player)
        _pendingRespawn[player] = nil
    end)

    print("[DeathService] Started — watching for Dead state transitions")
end


-- expose helper for unit tests to invoke respawn logic directly
function DeathService._RespawnNow(player: Player)
    _respawnPlayer(player)
end

return DeathService
