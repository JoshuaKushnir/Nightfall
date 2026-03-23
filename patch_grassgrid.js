const fs = require('fs');
let code = fs.readFileSync('src/client/modules/environment/GrassGrid.lua', 'utf8');

code = code.replace(
    /function GrassGrid:SetSurfaces\(surfaces: \{BasePart\}\)\n\t-- TBD \/ Optional, leaving empty for now based on acceptance criteria\nend/,
    `function GrassGrid:SetSurfaces(surfaces: {BasePart})
	self.Config.SurfaceFilter = surfaces
end`
);

fs.writeFileSync('src/client/modules/environment/GrassGrid.lua', code);
