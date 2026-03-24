const fs = require('fs');

let hc = fs.readFileSync('src/client/controllers/HeavenEnvironmentController.lua', 'utf8');
hc = hc.replace(
    'GrassValMax = 0.70,',
    'GrassValMax = 0.70,\n\tSurfaceFilter = nil,'
);
fs.writeFileSync('src/client/controllers/HeavenEnvironmentController.lua', hc);

let vc = fs.readFileSync('src/client/controllers/VoidEnvironmentController.lua', 'utf8');
vc = vc.replace(
    'GrassValMax = 0.4,',
    'GrassValMax = 0.4,\n\tSurfaceFilter = nil,'
);
fs.writeFileSync('src/client/controllers/VoidEnvironmentController.lua', vc);
