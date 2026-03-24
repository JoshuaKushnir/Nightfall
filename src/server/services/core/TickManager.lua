--!strict
-- Class: TickManager
-- Description: Centralized tick loop for batching periodic effects (#191).
-- Dependencies: RunService

local RunService = game:GetService("RunService")

local TickManager = {}

export type TickCallback = (dt: number) -> ()

type TickEntry = {
    id: string,
    callback: TickCallback,
    interval: number,
    timeSinceLastTick: number,
}

local activeTicks: { [string]: TickEntry } = {}
local connection: RBXScriptConnection? = nil

-- Registers a new periodic effect to the centralized tick loop.
function TickManager.Register(id: string, interval: number, callback: TickCallback)
    activeTicks[id] = {
        id = id,
        callback = callback,
        interval = interval,
        timeSinceLastTick = 0,
    }

    if not connection then
        TickManager._Start()
    end
end

-- Deregisters a periodic effect from the centralized tick loop.
function TickManager.Deregister(id: string)
    activeTicks[id] = nil

    local hasAny = false
    for _ in pairs(activeTicks) do
        hasAny = true
        break
    end

    if not hasAny and connection then
        TickManager._Stop()
    end
end

function TickManager._Start()
    if connection then return end
    connection = RunService.Heartbeat:Connect(function(dt: number)
        for id, entry in pairs(activeTicks) do
            entry.timeSinceLastTick += dt
            if entry.timeSinceLastTick >= entry.interval then
                entry.timeSinceLastTick %= entry.interval

                -- Execute callback in a separate thread to prevent yielding the main loop
                task.spawn(entry.callback, dt)
            end
        end
    end)
end

function TickManager._Stop()
    if connection then
        connection:Disconnect()
        connection = nil
    end
end

return TickManager
