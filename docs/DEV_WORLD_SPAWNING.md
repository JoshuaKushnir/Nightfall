# Dev World Spawning System

**Last Updated:** March 16, 2026  
**Related Issues:** [#178](https://github.com/JoshuaKushnir/Nightfall/issues/178) (World Design), [#175](https://github.com/JoshuaKushnir/Nightfall/issues/175) (Enemy AI)

---

## Overview

The dev world spawning system (`DevWorldBootstrap.server.lua`) procedurally creates all game zones and enemy spawn points for Ring 1-4 in Studio. This enables end-to-end gameplay testing and provides spawn infrastructure for services to build actual enemy AI.

**Studio-Only:** This script is guarded by `RunService:IsStudio()` and never runs on published servers.

---

## What Gets Spawned

### Zones (12 total)

| Ring | Zone | Position | Enemy Count |
|------|------|----------|-------------|
| **Ring 1** | Canopy Road | (-100, 1, 250) | 3 |
| | Drowned Meadow | (0, 1, 300) | 3 |
| | Ashward Fringe | (120, 1, 280) | 3 |
| **Ring 2** | Ashroads | (-150, 1, 420) | 3 |
| | Dried Basin | (0, 1, 480) | 3 |
| | Choir Outpost | (150, 1, 450) | 3 |
| **Ring 3** | Hall of Accord | (-150, 1, 620) | 3 |
| | Collapsed Archive | (0, 1, 680) | 3 |
| | Memorial Quarter | (150, 1, 650) | 3 |
| **Ring 4** | Windfield | (-150, 1, 820) | 3 |
| | Sunken Choir Shrine | (0, 1, 880) | 3 |
| | Null Approach | (150, 1, 850) | 3 |

### Enemy Spawn Points (36 total)

Each zone has 3 enemy spawn points, tagged by type:

**Ring 1 — Verdant Shelf**
- `HollowedSpawn`: Hollowed Drifter, Hollowed Sentinel, Hollowed Fisher, etc.
- `CreatureSpawn`: Greyback, Murk Lurker, Fringe Creeper, Dimling, Ash Hound, etc.

**Ring 2 — Ashfeld**
- `HollowedSpawn`: Hollowed Channeler, Petrified Hollowed, Hollow Revenant
- `ChoirSpawn`: Choir Initiate, Choir Penitent, Choir Vanguard, Choir Archivist, Choir Ascendant, Shrine Warden
- `CreatureSpawn`: Ash Hound, Basin Stalker, Ashen Familiar

**Ring 3 — Vael Depths**
- `PreservedSpawn`: Preserved (Seated), Preserved (Standing), Warden Ghost
- `ThreadweaverSpawn`: Threadweaver Lurker, Threadweaver Hunter
- `CreatureSpawn`: Archive Crawler
- `EnvironmentalSpawn`: Memory Shade
- `HollowedSpawn`: Hollow Revenant, Grief-Touched

**Ring 4 — Gloam**
- `VaelbornSpawn`: Vaelborn Drifter, Vaelborn Pack
- `ChoirSpawn`: Choir Ascendant, Shrine Warden, Hollowed Pilgrim
- `HollowedSpawn`: Null-Touched Hollowed, Hollowed Pilgrim
- `PreservedSpawn`: Wandering Preserved
- `EnvironmentalSpawn`: Gloam Shade, Convergence Herald

---

## Spawn Point Attributes

Each spawn point is tagged with a CollectionService tag (see above) and has custom attributes:

```lua
-- On each spawn part:
spawnPart:SetAttribute("EnemyType", "SpawnerType")  -- e.g., "HollowedDrifter"
spawnPart:SetAttribute("Ring", "Ring1")             -- Ring identifier
spawnPart:SetAttribute("Zone", "CanopyRoad")        -- Zone name
```

Services use these attributes for discovery and context.

---

## How Services Integrate

### Reading Spawn Points

All enemy services follow this pattern from `HollowedService`:

```lua
-- During Start(), read all spawn points of a specific tag
for _, spawnPart in CollectionService:GetTagged("HollowedSpawn") do
    local enemyType = spawnPart:GetAttribute("EnemyType")
    local ring = spawnPart:GetAttribute("Ring")
    local zone = spawnPart:GetAttribute("Zone")
    
    -- Create enemy instance at spawn location
    local enemy = CreateEnemyInstance(enemyType, spawnPart.Position)
    RegisterEnemyForCombat(enemy)
end
```

### Service Tags (Phase 4b Implementation)

Services that need to be created will read these tags:

| Service | Tag | Enemies |
|---------|-----|---------|
| `HollowedService` | `HollowedSpawn` | ✅ Ready (existing) |
| `CreatureService` | `CreatureSpawn` | ⏳ Create in Phase 4b |
| `ChoirService` | `ChoirSpawn` | ⏳ Create in Phase 4b |
| `PreservedService` | `PreservedSpawn` | ⏳ Create in Phase 4b |
| `ThreadweaverService` | `ThreadweaverSpawn` | ⏳ Create in Phase 4b |
| `VaelbornService` | `VaelbornSpawn` | ⏳ Create in Phase 4b |
| `EnvironmentalService` | `EnvironmentalSpawn` | ⏳ Create in Phase 4b |

---

## Workspace Structure

```
Workspace/
  Ring0Ground           — Safe zone, no enemies
  
  Ring1Trigger          — Zone detection volume
  Ring1Ground           — Walk surface (forest)
  Ring1Entrance         — Bright yellow pad for easy entry into Ring 1
  
  Ring1_CanopyRoad_Trigger      — Zone volume
  Ring1_CanopyRoad_HollowedDrifter      — Spawn point (tagged HollowedSpawn)
  Ring1_CanopyRoad_HollowedSentinel     — Spawn point (tagged HollowedSpawn)
  Ring1_CanopyRoad_Greyback             — Spawn point (tagged CreatureSpawn)
  
  Ring1_DrownedMeadow_Trigger   — Zone volume
  [Enemy spawns...]
  
  Ring1_AshwardFringe_Trigger   — Zone volume
  [Enemy spawns...]
  
  Ring2Trigger          — Zone detection volume
  Ring2Ground           — Walk surface (ash)
  [All Ring 2 zones and enemies...]
  
  Ring3Trigger          — Zone detection volume
  Ring3Ground           — Walk surface (ancient stone)
  [All Ring 3 zones and enemies...]
  
  Ring4Trigger          — Zone detection volume
  Ring4Ground           — Walk surface (dark)
  [All Ring 4 zones and enemies...]
```

---

## Visual Debugging

**Ring Colors** (in Studio only):

- **Ring 1 (Verdant Shelf)**: Forest green ground, green trigger
- **Ring 2 (Ashfeld)**: Dark grey ground, dark red trigger
- **Ring 3 (Vael Depths)**: Slate blue ground, slate blue trigger
- **Ring 4 (Gloam)**: Dark slate blue ground, midnight blue trigger

**Spawn Points**: Dark red 2×2 stud floating spheres (mostly transparent for debugging).

---

## How to Test

1. **Start Studio game** (DevWorldBootstrap runs automatically)
2. **Output console** shows:
   ```
   [DevWorldBootstrap] Creating all ring zones and enemy spawns...
   [DevWorldBootstrap] Setting up Ring1...
     ✓ Created Ring1Ground
     ✓ Created Ring1Trigger
     ✓ Created zone trigger: CanopyRoad
     ✓ Created 3 enemy spawns in CanopyRoad
     [...]
   [DevWorldBootstrap] ✅ All zones and enemy spawns created!
   [DevWorldBootstrap] Ring 1: 3 zones × 3 enemies = 9 spawn points
   [DevWorldBootstrap] Ring 2: 3 zones × 3 enemies = 9 spawn points
   [DevWorldBootstrap] Ring 3: 3 zones × 3 enemies = 9 spawn points
   [DevWorldBootstrap] Ring 4: 3 zones × 3 enemies = 9 spawn points
   [DevWorldBootstrap] Total: 36 enemy spawn points + 12 zone triggers
   ```

3. **Navigate town** to Ring 1 Entrance (yellow pad)
4. **Walk forward** to see enemies spawn (currently only Ring 1 enemies visible if `HollowedService` is running)
5. **Open Workspace** tab to see zone/enemy structure

---

## Implementation Notes

### Current Status
- ✅ Ring 1 enemies: `HollowedService` reads `HollowedSpawn` tags
- ⏳ Ring 1 creatures: Need `CreatureService`
- ⏳ Ring 2-4: Need services for Choir, Preserved, Threadweaver, Vaelborn, etc.

### Next Steps (Phase 4b)

Issue #175 will implement:
1. Basic AI template (pathfinding, aggro, attack)
2. `CreatureService` for Ring 1 animals
3. `ChoirService` for Ring 2 humanoids
4. `PreservedService` for Ring 3 echoes
5. `ThreadweaverService` for trap builders
6. `VaelbornService` for alien entities
7. `EnvironmentalService` for hazards

Each service will follow `HollowedService` pattern:
- Read spawn tags during `Start()`
- Create instances and register for combat
- Store references for network sync and state management

---

## Spec Reference

Full zone and enemy specifications: [docs/Game Plan/World_Design.md](Game%20Plan/World_Design.md)

For each enemy type, review:
- Core mechanic in World_Design.md
- Placeholder stat values (HP, damage, etc.)
- Patrol/aggro ranges
- Special behaviors (status effects, phase transitions, etc.)

---

## Technical Details

### Why Procedural Spawning?

- **Studio workflows**: Quickly test new zones without manual Studio geometry
- **Replicability**: Exact same spawn layout every session
- **Scalability**: Easy to add/remove zones or enemies
- **Service testing**: Spawn infrastructure ready for AI development

### Why CollectionService Tags?

- Services can find spawn points at runtime via `GetTagged()`
- No need for hardcoded folder structures
- Attributes store context (EnemyType, Ring, Zone) for service logic
- Scales to hundreds of spawns without performance overhead

### Color Coding

Studio-only visualization:
- Transparent zone triggers visible but don't affect gameplay
- Color-coded by ring for quick orientation
- Spawn points are near-invisible (0.9 transparency) but positioned visibly in explorer

---

## Troubleshooting

### No enemies visible in Studio?
- Check that services (e.g., `HollowedService`) are initialized and `Start()` was called
- Open Workspace explorer → verify spawn points exist with correct tags
- Check output console for initialization errors

### Spawn points in wrong ring?
- Verify `Ring` attribute in spawner properties
- Check WorldBootstrap position calculations for ring spacing
- Cross-reference ring positions in code vs. World_Design.md

### Zones not detected (ZoneService reporting wrong ring)?
- Player may be between zones; stand inside bright colored zone volume
- Zone reports as Ring 0 (safe zone) until standing inside Ring volume
- See [ZoneService.lua](../src/server/services/ZoneService.lua) for trigger logic

---

## References

- **DevWorldBootstrap**: [src/server/DevWorldBootstrap.server.lua](../src/server/DevWorldBootstrap.server.lua)
- **HollowedService**: [src/server/services/HollowedService.lua](../src/server/services/HollowedService.lua)
- **World Design**: [docs/Game Plan/World_Design.md](Game%20Plan/World_Design.md)
- **Issue #175**: Basic enemy AI implementation
- **Issue #178**: World & Enemy Roster Design (completed)

