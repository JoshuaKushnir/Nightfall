--!strict
local PhysicsOptimizer = {}
function PhysicsOptimizer.new() return setmetatable({}, {__index=PhysicsOptimizer}) end
function PhysicsOptimizer:Start() end
return PhysicsOptimizer
