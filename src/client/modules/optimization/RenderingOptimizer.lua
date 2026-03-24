--!strict
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RenderingOptimizer = {}
RenderingOptimizer.__index = RenderingOptimizer

function RenderingOptimizer.new()
    local self = setmetatable({}, RenderingOptimizer)
    self._active = false
    self._fps = 60
    self._frames = 0
    self._lastTime = tick()
    return self
end

function RenderingOptimizer:Start()
    self._active = true
    RunService.Heartbeat:Connect(function()
        self._frames = self._frames + 1
        local now = tick()
        if now - self._lastTime >= 1 then
            self._fps = self._frames
            self._frames = 0
            self._lastTime = now
        end
    end)
end

function RenderingOptimizer:GetFPS(): number
    return self._fps
end

return RenderingOptimizer
