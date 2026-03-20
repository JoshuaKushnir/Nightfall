# Spawning System Flow Diagram

## Server Startup Flow

```
┌─────────────────────────────────────┐
│  HollowedService:Start()            │
└──────────────┬──────────────────────┘
               │
               ├─→ Load SpawnerConfig.GetDefaultConfig()
               │   ├─ Ring1_Verdant (MobCap=4)
               │   ├─ Ring1_Ruins (MobCap=3)
               │   └─ Ring1_Cavern (MobCap=2)
               │
               └─→ Start Heartbeat Loop
                   ├─ AI Tick (every 0.2s per mob)
                   └─ Spawn Check (every 5s) ─→ [See Spawn Cycle below]
```

## Spawn Cycle (Every 5 Seconds)

```
┌──────────────────────────────────────────────┐
│  _TrySpawnRespawns()                         │
└──────────────┬───────────────────────────────┘
               │
               └─→ For each SpawnZone:
                   │
                   ├─→ Count living enemies in zone
                   │   └─ _CountInstancesInArea(zone.AreaName)
                   │      └─ Return count of non-Dead instances
                   │
                   ├─→ Calculate available slots
                   │   └─ spotsAvailable = zone.MobCap - currentCount
                   │
                   ├─→ Check if should spawn this cycle
                   │   └─ IF spotsAvailable > 0 AND math.random() < 0.6
                   │
                   ├─→ Find safe spawn position
                   │   └─ SpawnerConfig.FindSafeSpawnPosition()
                   │      │
                   │      ├─→ Generate 5 random candidates
                   │      │   └─ Within zone.SearchRadius of CenterPosition
                   │      │
                   │      └─→ Test each candidate:
                   │          │
                   │          ├─ Distance to existing mobs
                   │          │  └─ IF dist < CollisionCheckRadius → SKIP
                   │          │
                   │          ├─ Distance to players
                   │          │  └─ IF dist < MinSpawnDistance → SKIP
                   │          │
                   │          └─ IF both checks pass → RETURN position
                   │
                   ├─→ Spawn enemy if position found
                   │   └─ HollowedService.SpawnInstance(variant, CFrame)
                   │      └─ Create Model, set State="Patrol"
                   │
                   └─→ Track assignment
                       ├─ _instanceAreaMap[instanceId] = zone.AreaName
                       └─ Log: "Spawned X in Y (count/cap)"
```

## Enemy Lifecycle

```
┌──────────────────────────────────────┐
│  Spawn Check finds safe position     │
└──────────────┬──────────────────────┘
               │
               ├─→ HollowedService.SpawnInstance()
               │   └─ Create Model + Data struct
               │       └─ State = "Patrol"
               │           └─ _instances[id] = data
               │
               ├─→ _TrySpawnRespawns() tracks zone
               │   └─ _instanceAreaMap[id] = areaName
               │
               ├─→ AI Loop processes each frame
               │   └─ _TickAI() every 0.2s
               │       ├─ Check for players (AggroRange)
               │       │  └─ IF found → State = "Aggro"
               │       ├─ Check attack range
               │       │  └─ IF reached → State = "Attacking"
               │       └─ Patrol logic / Movement
               │
               ├─→ Combat occurs
               │   └─ HitConfirmed event received
               │       └─ Damage applied to enemy
               │
               ├─→ Enemy dies (CurrentHealth = 0)
               │   └─ State = "Dead"
               │       └─ Play death animation
               │           └─ Wait RespawnDelay
               │
               ├─→ HollowedService.DespawnInstance()
               │   └─ Destroy Model
               │       └─ _instances[id] = nil
               │           └─ _instanceAreaMap[id] = nil
               │
               └─→ Spawn Check finds available slot
                   └─ [Cycle repeats]
```

## Collision Prevention Logic

```
┌────────────────────────────────────────────┐
│  FindSafeSpawnPosition()                   │
│  (Testing one candidate position)          │
└────────────────────┬──────────────────────┘
                     │
                     ├─→ Check vs Existing Mobs
                     │   │
                     │   ├─ Get all active instances
                     │   ├─ For each: calculate distance
                     │   │
                     │   └─ IF distance < 10 studs
                     │       └─ REJECT candidate (too close)
                     │
                     ├─→ Check vs Players
                     │   │
                     │   ├─ Get all connected players
                     │   ├─ Get their HumanoidRootPart position
                     │   ├─ Calculate distance
                     │   │
                     │   └─ IF distance < 40 studs
                     │       └─ REJECT candidate (too close)
                     │
                     └─→ IF both checks pass
                         └─ ACCEPT position ✓
                            └─ Return to _TrySpawnRespawns()
```

## Mob Cap Enforcement Example

```
Ring1_Verdant Zone (MobCap = 4)

Scenario Timeline:
─────────────────────────────────────────────

T=0s:  Spawn Check #1
       Current: 0 mobs
       Available: 4 - 0 = 4 slots ✓
       Random < 0.6? YES → Spawn mob #1
       Status: ■□□□ (1/4)

T=5s:  Spawn Check #2
       Current: 1 mob (alive)
       Available: 4 - 1 = 3 slots ✓
       Random < 0.6? YES → Spawn mob #2
       Status: ■■□□ (2/4)

T=10s: Spawn Check #3
       Current: 2 mobs (alive)
       Available: 4 - 2 = 2 slots ✓
       Random < 0.6? YES → Spawn mob #3
       Status: ■■■□ (3/4)

T=15s: Spawn Check #4
       Current: 3 mobs (alive)
       Available: 4 - 3 = 1 slot ✓
       Random < 0.6? YES → Spawn mob #4
       Status: ■■■■ (4/4) [AT CAP]

T=20s: Spawn Check #5
       Current: 4 mobs (alive)
       Available: 4 - 4 = 0 slots ✗
       → Skip spawn for this zone
       Status: ■■■■ (4/4) [AT CAP]

T=25s: Player kills mob #1
       Current: 3 mobs (alive)
       Available: 4 - 3 = 1 slot ✓

T=30s: Spawn Check #6
       Random < 0.6? YES → Spawn mob #5
       Status: ■■■□ (4/4) [CAP RESTORED]
```

## Multi-Zone Coordination Example

```
Three zones spawning independently:

Ring1_Verdant (MobCap=4)        Ring1_Ruins (MobCap=3)        Ring1_Cavern (MobCap=2)
────────────────────────        ──────────────────────        ──────────────────────

T=5s:  Spawn Check
  Verdant:  Current=0 → Spawn #1        Ruins:   Current=0 → Spawn #1      Cavern:  Current=0 → Spawn #1
  Status: 1/4 ✓                         Status:  1/3 ✓                      Status:  1/2 ✓

T=10s: Spawn Check
  Verdant:  Current=1 → Spawn #2        Ruins:   Current=1 → Spawn #2      Cavern:  Current=1 → SKIP (50% chance)
  Status: 2/4 ✓                         Status:  2/3 ✓                      Status:  1/2 ✓

T=15s: Spawn Check
  Verdant:  Current=2 → Spawn #3        Ruins:   Current=2 → Spawn #3      Cavern:  Current=1 → Spawn #2
  Status: 3/4 ✓                         Status:  3/3 ✗ [AT CAP]             Status:  2/2 ✗ [AT CAP]

T=20s: Spawn Check
  Verdant:  Current=3 → Spawn #4        Ruins:   Current=3 → SKIP           Cavern:  Current=2 → SKIP
  Status: 4/4 ✗ [AT CAP]                Status:  3/3 ✗ [AT CAP]             Status:  2/2 ✗ [AT CAP]

Result: All zones at their respective caps, population balanced
```

## Configuration Override Flow

```
┌────────────────────────────────────┐
│  At Runtime (e.g., difficulty      │
│  change or testing)                │
└────────────────────┬───────────────┘
                     │
                     ├─→ Create new SpawnerConfig
                     │   local newConfig = SpawnerConfig.GetDefaultConfig()
                     │   newConfig.SpawnZones[1].MobCap = 6  -- Increase Verdant
                     │
                     ├─→ Apply to HollowedService
                     │   HollowedService.SetSpawnerConfig(newConfig)
                     │
                     └─→ Next spawn check uses new config
                         └─ No existing mobs affected
                             └─ Only new spawns follow new caps
```

## State Transitions During Spawn

```
┌──────────────────┐
│  None (not yet   │
│  in instance map)│
└────────┬─────────┘
         │
         ├─→ HollowedService.SpawnInstance(variant, CFrame)
         │
         ├─→ Create Model at CFrame
         │
         └─→ Initialize HollowedData
             ├─ State = "Patrol"
             ├─ CurrentHealth = MaxHealth
             ├─ CurrentPoise = MaxPoise
             └─ Target = nil
                 │
                 └─→ Ready for AI tick
                     ├─ Check for nearby players
                     ├─ Patrol or Aggro
                     └─ Combat if engaged
```

---

**Legend:**
- `■` = One active mob
- `□` = Available slot (no mob)
- `✓` = Condition met (spawn attempt)
- `✗` = Condition not met (skip spawn)
- `→` = Process flow
- `T=Xs` = Time in seconds
