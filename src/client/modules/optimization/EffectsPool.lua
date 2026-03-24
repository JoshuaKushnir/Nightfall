--!strict
local EffectsPool = {}
EffectsPool.__index = EffectsPool

function EffectsPool.new(template, initialSize)
    local self = setmetatable({}, EffectsPool)
    self._pool = {}
    self._template = template
    for i=1, initialSize or 10 do
        table.insert(self._pool, template:Clone())
    end
    return self
end

function EffectsPool:Get()
    if #self._pool > 0 then return table.remove(self._pool) end
    return self._template:Clone()
end

function EffectsPool:Return(obj)
    table.insert(self._pool, obj)
end

return EffectsPool
