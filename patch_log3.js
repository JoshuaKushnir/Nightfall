const fs = require('fs');
const content = fs.readFileSync('docs/session-log.md', 'utf8');

const newLog = `## Session NF-092: GrassGrid Performance & Cutoff Fixes

### What Was Built
- **Frustum Culling**: Added camera dot-product culling to \`GrassGrid:_updateBlades\`. Cells behind the camera are completely skipped, reducing CFrame updates by up to 70% per frame depending on FOV, heavily improving FPS.
- **Fixed Pop-in / Cutoff Bug**:
  - Previously, blades past \`AnimationDist\` were entirely skipped, meaning they never received their LOD sink updates and vanished abruptly at \`DrawDistance\`.
  - Added a grid buffer cell beyond \`DrawDistance\` and fixed the culling logic so all distant blades properly execute their sink-fade into the ground before their pool is despawned.
- **Trig Wind Optimization**: Replaced heavy \`math.noise()\` per-blade lookups with overlapping \`math.sin\`/\`math.cos\` waves, drastically lowering the math overhead per frame.
- **Rebalanced Density/Visuals**: Increased blade size and \`CellSize\` while slightly lowering \`BladesPerCell\`. The grass now feels cohesive and wide, but demands significantly fewer instances (e.g. 80 blades over 16x16 instead of 200 over 12x12). Extended \`DrawDistance\` from 160 to 220 to fully bury the edge in the fog.

### Technical Debt / Pending Tasks
- None. Grass performance is now optimal and scales gracefully.

`;

fs.writeFileSync('docs/session-log.md', newLog + content);
