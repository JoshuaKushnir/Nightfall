--!strict
--[[
    Class: TrainingToolService
    Description: Server authority for training tool usage — allows players to consume
                 tangible items to directly increase stats, replacing abstract StatPoints
                 during transition period.
    
    Public API:
        TrainingToolService.UseTrainingTool(player, itemId) -> (boolean, string?)
            → Consumes one training tool of the given itemId and applies its stat increase.
            → Returns success and optional error message.
            
    Dependencies: DataService, NetworkService, InventoryService, ProgressionService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService: any = nil
local ProgressionService: any = nil
local NetworkService: any = nil
local ProgressionTypes = require(ReplicatedStorage.Shared.types.ProgressionTypes)
local ItemTypes = require(ReplicatedStorage.Shared.types.ItemTypes)
local ItemRegistry = require(ReplicatedStorage.Shared.modules.ItemRegistry)

local TrainingToolService = {}
TrainingToolService._initialized = false

-- Cooldown tracking: [player.UserId] = { [statName] = lastUsedTime }
local _cooldowns = {}

-- Clean up cooldowns when player leaves to prevent memory leak
local function _onPlayerRemoving(player: Player)
	_cooldowns[player.UserId] = nil
end

-- Register player removal handler
Players.PlayerRemoving:Connect(_onPlayerRemoving)

--[[
    UseTrainingTool(player, itemId) -> (boolean, string?)
    Consumes one training tool of the given itemId and applies its stat increase.
    
    @param player  The player using the tool
    @param itemId  The ItemId of the training tool to use
    @returns (success, errorReason?)
]]
function TrainingToolService.UseTrainingTool(player: Player, itemId: string): (boolean, string?)
    -- Validate itemId is a known training tool via ItemRegistry
    local toolDef = ItemRegistry.Get(itemId)
    if not toolDef then
        warn(("[TrainingToolService] %s attempted to use unknown item: %s"):format(player.Name, itemId))
        return false, "UnknownItem"
    end
    
    -- Verify this is actually a training tool
    if toolDef.Category ~= "Tools" or not toolDef.TrainingToolId then
        warn(("[TrainingToolService] %s attempted to use non-training tool: %s"):format(player.Name, itemId))
        return false, "NotTrainingTool"
    end
    
    -- Check cooldown for this stat type
    local cooldownSeconds = toolDef.Cooldown or 5  -- Default 5 second cooldown
    local statName = toolDef.StatToIncrease
    local userId = player.UserId
    
    if not _cooldowns[userId] then
        _cooldowns[userId] = {}
    end
    
    local lastUsed = _cooldowns[userId][statName] or 0
    local currentTime = tick()  -- Use tick() for sub-second precision
    
    if currentTime - lastUsed < cooldownSeconds then
        local remaining = cooldownSeconds - (currentTime - lastUsed)
        return false, "CooldownActive"
    end
    
    -- Get player profile
    local profile = DataService:GetProfile(player)
    if not profile then
        return false, "NoProfile"
    end

    -- Lazy load InventoryService to avoid circular dependency
    local InventoryService = require(script.Parent.InventoryService)
    
    -- Check if player has the item in inventory (inline check since HasItem doesn't exist)
    local hasItem = false
    for _, v in ipairs(profile.Inventory or {}) do
        if v.Id == itemId then
            hasItem = true
            break
        end
    end
    if not hasItem then
        return false, "ItemNotFound"
    end
    
    -- Consume one item using RemoveItem (ConsumeItem doesn't exist)
    local success = InventoryService.RemoveItem(player, itemId)
    if not success then
        warn(("[TrainingToolService] %s failed to consume item %s"):format(player.Name, itemId))
        return false, "ConsumeFailed"
    end
    
    -- Apply the stat increase via ProgressionService
    local amount = toolDef.Amount
    
    local allocSuccess, allocError = ProgressionService.AllocateStat(player, statName, amount)
    if not allocSuccess then
        -- Refund the consumed item on failure (player shouldn't lose item if stat can't be allocated)
        -- Use GiveItem instead of AddItem
        InventoryService.GiveItem(player, toolDef)
        warn(("[TrainingToolService] %s failed to allocate stat %s+%d: %s (item refunded)"):format(player.Name, statName, amount, allocError or "unknown"))
        return false, allocError or "StatAllocationFailed"
    end
    
    -- Update cooldown timestamp for this stat
    _cooldowns[userId][statName] = currentTime
    
    -- Success! Notify client
    local statValue = profile.Stats[statName] or 0
    local remainingPoints = profile.StatPoints or 0
    
    -- We don't need to send a custom event because AllocateStat already sends StatAllocated
    -- But we could send a specific training tool used event for UI feedback
    -- For now, rely on the existing StatAllocated event
    
    print(("[TrainingToolService] %s used %s: +%d %s (total: %d, unspent points: %d)"):format(player.Name, itemId, amount, statName, statValue, remainingPoints))
    
    return true, nil
end

--[[
    Init() -> void
    Initializes the service.
]]
function TrainingToolService:Init(dependencies)

    if dependencies and dependencies.DataService then
        DataService = dependencies.DataService
    else
        DataService = require(script.Parent.DataService)
    end

    if dependencies and dependencies.ProgressionService then
        ProgressionService = dependencies.ProgressionService
    else
        ProgressionService = require(script.Parent.ProgressionService)
    end

    if dependencies and dependencies.NetworkService then
        NetworkService = dependencies.NetworkService
    else
        NetworkService = require(script.Parent.NetworkService)
    end
    print("[TrainingToolService] Initializing...")
    self._initialized = true
    print("[TrainingToolService] Initialized successfully")
end

--[[
    Start() -> void
    Starts the service and sets up any necessary connections.
]]
function TrainingToolService:Start()
    print("[TrainingToolService] Starting...")
    -- Register handler for UseTrainingTool events from clients
    NetworkService:RegisterHandler("UseTrainingTool", function(player: Player, packet: any)
        if type(packet) ~= "table"
            or type(packet.Slot) ~= "string"
            or type(packet.ItemId) ~= "string" then
            warn(("[TrainingToolService] Bad UseTrainingTool packet from %s"):format(player.Name))
            return
        end
        TrainingToolService.UseTrainingTool(player, packet.ItemId)
    end)
    print("[TrainingToolService] Started successfully")
end

return TrainingToolService
