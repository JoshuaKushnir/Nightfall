--!strict
local RenderingOptimizer = require(script.Parent.RenderingOptimizer)
local CharacterCuller = require(script.Parent.CharacterCuller)
local PhysicsOptimizer = require(script.Parent.PhysicsOptimizer)

local RenderingOptimizationSetup = {}

function RenderingOptimizationSetup.Init()
    local renderOpt = RenderingOptimizer.new()
    local charCuller = CharacterCuller.new()
    local physOpt = PhysicsOptimizer.new()
    
    renderOpt:Start()
    charCuller:Start()
    physOpt:Start()
    
    return {
        Render = renderOpt,
        Character = charCuller,
        Physics = physOpt
    }
end

return RenderingOptimizationSetup
