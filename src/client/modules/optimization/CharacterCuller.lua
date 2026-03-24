--!strict
local CharacterCuller = {}
function CharacterCuller.new() return setmetatable({}, {__index=CharacterCuller}) end
function CharacterCuller:Start() end
return CharacterCuller
