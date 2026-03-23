const fs = require('fs');
let code = fs.readFileSync('src/shared/types/GrassTypes.lua', 'utf8');

code = code.replace(
    'GrassValMax: number,',
    'GrassValMax: number,\n\tSurfaceFilter: {BasePart}?, -- Optional list of surfaces to place grass on'
);

fs.writeFileSync('src/shared/types/GrassTypes.lua', code);
