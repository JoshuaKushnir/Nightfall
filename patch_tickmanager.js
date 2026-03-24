const fs = require('fs');
const path = require('path');

const dir = 'src/shared/abilities/';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.lua'));

for (const file of files) {
    let content = fs.readFileSync(path.join(dir, file), 'utf8');
    
    // Add TickManager to GetService
    if (content.includes('elseif name == "DummyService" then')) {
        let tmStr = `	elseif name == "TickManager" then
		if RunService:IsServer() then
			local success, result = pcall(function() return require(game:GetService("ServerScriptService").Server.services.core.TickManager) end)
			_services[name] = success and result or false
		else
			_services[name] = false
		end
`;
        content = content.replace('	elseif name == "DummyService" then', tmStr + '	elseif name == "DummyService" then');
        fs.writeFileSync(path.join(dir, file), content);
        console.log("Added TickManager to", file);
    }
}
