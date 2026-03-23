const fs = require('fs');
const path = require('path');

const dir = 'src/shared/abilities/';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.lua'));

const cacheHeader = `
-- Service caching to avoid per-hit require overhead (Optimization #189)
local _services = {}
local function GetService(name)
	if _services[name] ~= nil then return _services[name] end
	local RunService = game:GetService("RunService")
	
	if name == "NetworkProvider" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
	elseif name == "HitboxService" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.modules.combat.HitboxService)
	elseif name == "PostureService" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.combat.PostureService) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "CombatService" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.combat.CombatService) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "DummyService" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.entities.DummyService) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	end
	
	return _services[name]
end
`;

for (const file of files) {
    let content = fs.readFileSync(path.join(dir, file), 'utf8');
    let original = content;
    
    const matchAndReplace = (regex, replacement) => {
        content = content.replace(regex, replacement);
    };

    matchAndReplace(/local np = require\(.+?NetworkProvider\)/g, 'local np = GetService("NetworkProvider")');
    matchAndReplace(/local NetworkProvider = require\(.+?NetworkProvider\)/g, 'local NetworkProvider = GetService("NetworkProvider")');
    matchAndReplace(/local HitboxService = require\(.+?HitboxService\)/g, 'local HitboxService = GetService("HitboxService")');
    matchAndReplace(/local PostureService = require\(.+?PostureService\)/g, 'local PostureService = GetService("PostureService")');
    matchAndReplace(/local DummyService = require\(.+?DummyService\)/g, 'local DummyService = GetService("DummyService")');
    matchAndReplace(/local DummyService = pcall[^\n]+or nil/g, 'local DummyService = GetService("DummyService") or nil');
    
    matchAndReplace(/return require\(.+?NetworkProvider\)/g, 'return GetService("NetworkProvider")');
    matchAndReplace(/return require\(.+?CombatService\)/g, 'return GetService("CombatService")');
    matchAndReplace(/return require\(.+?PostureService\)/g, 'return GetService("PostureService")');
    matchAndReplace(/return require\(.+?DummyService\)/g, 'return GetService("DummyService")');

    if (content !== original) {
        if (!content.includes('Optimization #189')) {
            if (content.startsWith('--!strict\n')) {
                content = content.replace('--!strict\n', '--!strict\n' + cacheHeader);
            } else {
                content = cacheHeader + content;
            }
        }
        
        fs.writeFileSync(path.join(dir, file), content);
        console.log("Patched", file);
    }
}
