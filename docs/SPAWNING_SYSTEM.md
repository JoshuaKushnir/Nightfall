# Area-Based Dynamic Spawning System

## Overview

The dynamic spawning system for Hollowed enemies replaces static tag-based spawning with an intelligent, area-aware system that:

- **Spawns enemies dynamically** throughout Ring 1 based on configurable zones
- **Enforces mob caps** per area to prevent overcrowding
- **Prevents spawn collisions** by checking for nearby enemies and players
- **Feels immersive** with natural population dynamics rather than static spawn points

## Architecture

### Components

#### 1. SpawnerConfig Module (`src/server/modules/SpawnerConfig.lua`)

Provides data structures and helper functions for spawning:

```lua
export type SpawnZone = {
    AreaName: string,           -- e.g. "Ring1_Verdant"
    Ring: number,               -- Ring number (1–5)
    MobCap: number,             -- Max concurrent enemies
    CenterPosition: Vector3,    -- Center of the spawn area
    SearchRadius: number,       -- Radius to spawn within (studs)
    SpawnRadius: number,        -- Collision check radius
}
```

**Key Functions:**

- `GetDefaultConfig()` → Returns default spawn zones for Ring 1
- `FindZone(zoneList, areaName)` → Find a zone by name
- `FindZonesByRing(zoneList, ring)` → Get all zones in a ring
- `GenerateSpawnCandidates(zone, count)` → Create random spawn positions
- `IsSpawnPositionSafe(pos, instances, radius)` → Check collision with mobs
- `IsSpawnPositionFarFromPlayers(pos, players, distance)` → Check player proximity
- `FindSafeSpawnPosition(zone, instances, ...)` → Find best spawn location

#### 2. HollowedService Integration

HollowedService now runs a periodic spawn check that:

1. **Counts active enemies per zone**
   ```lua
   local currentCount = _CountInstancesInArea("Ring1_Verdant")
   ```

2. **Checks available capacity**
   ```lua
   local spotsAvailable = zone.MobCap - currentCount
   if spotsAvailable > 0 then
       -- Attempt to spawn
   end
   ```

3. **Finds safe spawn positions**
   - Tests multiple random candidates within the zone
   - Rejects positions too close to other mobs
   - Rejects positions too close to players
   - Returns the first safe position found

4. **Spawns the enemy**
   ```lua
   local instanceId = HollowedService.SpawnInstance(randomVariant, spawnCF)
   _instanceAreaMap[instanceId] = zone.AreaName  -- Track for mob counting
   ```

## Configuration

### Default Spawn Zones (Ring 1)

```lua
SpawnZones = {
    {
        AreaName = "Ring1_Verdant",
        Ring = 1,
        MobCap = 4,
        CenterPosition = Vector3.new(0, 50, 0),
        SearchRadius = 60,
        SpawnRadius = 5,
    },
    {
        AreaName = "Ring1_Ruins",
        Ring = 1,
        MobCap = 3,
        CenterPosition = Vector3.new(100, 50, 100),
        SearchRadius = 50,
        SpawnRadius = 5,
    },
    {
        AreaName = "Ring1_Cavern",
        Ring = 1,
        MobCap = 2,
        CenterPosition = Vector3.new(-100, 30, -100),
        SearchRadius = 40,
        SpawnRadius = 5,
    },
}
```

### Spawn Parameters

```lua
CollisionCheckRadius = 10    -- Min distance between spawning mobs
RespawnCheckInterval = 5     -- How often to check for respawns (seconds)
MinSpawnDistance = 40        -- Don't spawn within this distance of players
```

## Customization

### Adjusting Spawn Zones

Edit `SpawnerConfig.GetDefaultConfig()` to modify zones:

**Parameters explained:**

- **AreaName**: Unique identifier for logging/tracking
- **Ring**: Which ring this zone belongs to (1–5)
- **MobCap**: Maximum concurrent enemies in this area
- **CenterPosition**: Approximate center of your zone (use workspace coordinates)
- **SearchRadius**: How far from center to randomly spawn (larger = more spread out)
- **SpawnRadius**: Used for collision checks (5–10 studs typical)

**Example: Add a fourth zone**

```lua
{
    AreaName = "Ring1_Forest",
    Ring = 1,
    MobCap = 5,
    CenterPosition = Vector3.new(-50, 40, 50),
    SearchRadius = 80,
    SpawnRadius = 5,
}
```

### Dynamic Configuration at Runtime

```lua
local HollowedService = require(path.to.HollowedService)
local newConfig = require(path.to.SpawnerConfig).GetDefaultConfig()

-- Modify the config
newConfig.SpawnZones[1].MobCap = 6  -- Increase mob cap for Verdant

-- Apply it
HollowedService.SetSpawnerConfig(newConfig)
```

## How It Works (Step by Step)

### Spawn Check Cycle (Every 5 seconds)

1. **For each spawn zone:**
   - Count living enemies in that zone
   - Calculate available spawn slots: `MobCap - CurrentCount`

2. **If slots available (60% spawn chance):**
   - Generate 5 random candidate positions within zone
   - Test each candidate:
     - Is it within `CollisionCheckRadius` of another mob? ✗ Skip
     - Is it within `MinSpawnDistance` of any player? ✗ Skip
     - Otherwise: ✓ Safe to spawn
   - If safe position found, spawn random variant

3. **Track the spawn:**
   - Record which zone the new instance belongs to
   - Log: `[HollowedService] Spawned basic_hollowed in Ring1_Verdant (2/4)`

4. **Continue AI loop:**
   - Existing enemies patrol, aggro, and attack normally
   - Dead enemies stay in the instance map until cleanup

### Respawn Cycle

When an enemy dies:
- State changes to "Dead"
- Instance remains in tracking map temporarily
- On next spawn check, area count doesn't include dead instances
- Spot becomes available for new spawn
- Dead instance is cleaned up when HollowedService.DespawnInstance() is called

## Performance Considerations

- **Spawn check every 5 seconds** (not per-frame) to avoid overhead
- **Max 5 candidate tests per zone per cycle** limits pathfinding cost
- **Single spawn per zone per cycle** prevents population spikes
- **Distance checks use simple magnitude calculation** (O(n) but n is typically <20)

## Logging and Debugging

### Startup Messages

```
[HollowedService] Spawning system configured with 3 areas
[HollowedService]  - Ring1_Verdant (Ring 1): MobCap=4, Center=(0, 50, 0), Radius=60
[HollowedService]  - Ring1_Ruins (Ring 1): MobCap=3, Center=(100, 50, 100), Radius=50
[HollowedService]  - Ring1_Cavern (Ring 1): MobCap=2, Center=(-100, 30, -100), Radius=40
[HollowedService] Started — Dynamic spawning and AI loop active
```

### Spawn Events

```
[HollowedService] Spawned basic_hollowed in Ring1_Verdant (2/4) at (15.2, 52.1, -8.3)
[HollowedService] Spawned ironclad_hollowed in Ring1_Ruins (1/3) at (95.5, 48.7, 110.2)
```

### No Safe Position Found

Silent retry on next cycle (no error logged). This is normal if:
- All candidates are too close to existing mobs
- All candidates are too close to players
- Zone is heavily populated near safe spawning distance

## Best Practices

### Setting CenterPosition

Use the **approximate center of your Ring** area in world coordinates:

```lua
-- In Roblox Studio:
1. Navigate to your Ring 1 area
2. Note the approximate center coordinates
3. Update CenterPosition in SpawnerConfig
```

### Tuning SearchRadius

- **Smaller (40–50)**: Enemies spawn in a tight cluster
- **Larger (60–80)**: Enemies spread throughout the area
- **Recommended**: 1.5–2x the area's actual size

### Mob Cap Balancing

Consider difficulty progression:

```lua
-- Easy zone: more enemies, more forgiving
{AreaName = "Ring1_Safe", MobCap = 6}

-- Medium zone: balanced
{AreaName = "Ring1_Verdant", MobCap = 4}

-- Hard zone: challenging
{AreaName = "Ring1_Ruins", MobCap = 2}
```

### Preventing Spawn Camping

`MinSpawnDistance = 40` prevents spawning enemies right on players. Adjust based on your difficulty:

- **Easier**: Increase to 60–80 studs
- **Harder**: Decrease to 20–30 studs

## Troubleshooting

### Enemies aren't spawning

1. **Check spawn zone config:** Verify `CenterPosition` is in your Ring
2. **Check mob caps:** Ensure zones aren't at cap: `[HollowedService] Spawned ... (X/Y)` log line
3. **Check player distance:** If players camp spawn center, `MinSpawnDistance` blocks all spawns
4. **Check logs:** Look for `[HollowedService] Spawning system configured...` message

### Too many enemies spawning

- **Reduce MobCap** in the zone's SpawnZone config
- **Increase CollisionCheckRadius** to require more distance between spawns
- **Lower spawn probability** by tweaking the `0.6` chance in `_TrySpawnRespawns()`

### Enemies spawning inside walls

- **Adjust CenterPosition** to be away from obstacles
- **Reduce SearchRadius** to spawn in safer area
- Future enhancement: Add raycasts to validate spawn positions

## Future Enhancements

- [ ] Raycast validation to ensure spawn height is on ground
- [ ] Weighted variant selection (some types rarer in certain zones)
- [ ] Dynamic difficulty scaling (increase MobCap during boss fights)
- [ ] Proximity-based spawn throttling (spawn slower if player is farming)
- [ ] Zone visualization debug mode (draw spawn zones in Studio)

## API Reference

### HollowedService

```lua
HollowedService.SetSpawnerConfig(newConfig: SpawnerConfig.SpawnerConfig)
-- Override the spawner configuration at runtime
```

### SpawnerConfig

```lua
SpawnerConfig.GetDefaultConfig() → SpawnerConfig
SpawnerConfig.FindZone(zoneList, areaName) → SpawnZone?
SpawnerConfig.FindZonesByRing(zoneList, ring) → {SpawnZone}
SpawnerConfig.GenerateSpawnCandidates(zone, count) → {Vector3}
SpawnerConfig.IsSpawnPositionSafe(pos, instances, radius) → boolean
SpawnerConfig.IsSpawnPositionFarFromPlayers(pos, players, distance) → boolean
SpawnerConfig.FindSafeSpawnPosition(zone, instances, ...) → Vector3?
```

## Integration with Other Systems

- **StateService**: Spawned enemies immediately enter "Patrol" state
- **NetworkProvider**: State changes broadcast to clients via `DummyStateChanged` events
- **CombatService**: Damage registration works normally for spawned enemies
- **DeathService**: Respawn eligibility tracks independently

---

**Last Updated:** 2026-03-17  
**Issue:** #143 (HollowedService — Ring 1 Enemy Spawning)