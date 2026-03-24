--!strict
--[[
    Class: TickManager
    Description: Centralized Tick Loop for Periodic Effects
    Dependencies: none
    Issue: #191
    Usage: Batches periodic effects like Burning and auras.
]]

local RunService = game:GetService("RunService")

local TickManager = {}
local effects = {}

function TickManager.Init(dependencies: any)
end

function TickManager.Start()
    RunService.Heartbeat:Connect(function(dt: number)
        for id, effect in pairs(effects) do
            effect.accumulated += dt
            if effect.accumulated >= effect.interval then
                effect.accumulated -= effect.interval
                local success, err = pcall(effect.callback)
                if not success then
                    warn("Tick callback failed", err)
                end
            end
        end
    end)
end

function TickManager.RegisterEffect(id: string, interval: number, callback: () -> ())
    effects[id] = {
        interval = interval,
        callback = callback,
        accumulated = 0
    }
end

function TickManager.DeregisterEffect(id: string)
    effects[id] = nil
end

return TickManager
