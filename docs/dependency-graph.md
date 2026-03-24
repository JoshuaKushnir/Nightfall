# Nightfall Dependency Graph & Initialization Order

## Overview
Nightfall uses a custom `Loader` module to orchestrate the lifecycle of Services (Server) and Controllers (Client). 
The lifecycle consists of three distinct phases to ensure safe dependency resolution without circular reference issues:
1. **Load Phase**: Modules are `require`d sequentially in alphabetical order. No logic should run in the main body of these modules other than returning the module table.
2. **Init Phase**: The `Init(dependencies)` method is called. Modules cache references to other modules injected via the `dependencies` parameter.
3. **Start Phase**: The `Start()` method is called in a strict, explicitly defined order to begin processing logic, listening to events, and establishing runtime state.

---

## Server Initialization (`src/server/runtime/init.lua`)

### Load Phase
Alphabetical loading via `Loader.LoadModules`.

### Init Phase dependencies injected:
- NetworkService
- DataService
- StateSyncService
- AspectService
- InventoryService
- ProgressionService
- PostureService
- EffectRunner
- PassiveSystem
- WeaponService
- DefenseService
- CombatService
- DeathService
- HollowedService
- ZoneService
- AbilitySystem
- TrainingToolService
- WitnessService

### Start Phase Order (Strict Dependency Graph)
1. **NetworkService**: Must start first; foundation for all client-server communication.
2. **StateSyncService**: Depends on `NetworkService`.
3. **DataService**: Loads player profiles.
4. **AspectService**: Needs core systems initialized.
5. **InventoryService**: Handles item logic.
6. **TrainingToolService**: Handles training tools.
7. **WeaponService**: Equip system (depends on `NetworkService` and `InventoryService`).
8. **DefenseService**: Defense mechanics.
9. **CombatService**: Combat validation, damage application.
10. **PostureService**: HP/Posture dual health (lazy-requires `CombatService`).
11. **ProgressionService**: Resonance, Ring caps, Discipline selection.
12. **DeathService**: Death & respawn pipeline (depends on `ProgressionService` for shard loss).
13. **HollowedService**: Enemy AI, patrol, aggro (depends on `ProgressionService` for kill grants).
14. **ZoneService**: Ring boundary detection (depends on `ProgressionService`).
15. **WitnessService**: Observation tracking (depends on `HollowedService`).
16. **EffectRunner**: Status effects.
17. **PassiveSystem**: Hook pipeline.
*Note: Any remaining services load alphabetically after this list.*

---

## Client Initialization (`src/client/runtime/init.lua`)

### Pre-requisites
1. Await `LocalPlayer`
2. Await `Character` and `Humanoid`
3. Disable default Roblox Backpack UI
4. Initialize `DebugInput`
5. Initialize `LoadingController`

### Load Phase
Alphabetical loading via `Loader.LoadModules`.

### Init Phase dependencies injected:
- NetworkController
- StateSyncController
- MovementController
- WeaponController
- ActionController
- CombatController
- AspectController
- InventoryController
- ProgressionController
- PlayerHUDController

### Start Phase Order (Strict Dependency Graph)
1. **NetworkController**: Foundation for server communication.
2. **CharacterCreationController**: Aspect picker (depends on `NetworkController`).
3. **DeathController**: ShardLost popup & respawn.
4. **StateSyncController**: State cache setup (must precede `MovementController`).
5. **MovementController**: Coyote time, jump buffer, sprint logic.
6. **WeaponController**: Equip state (must precede `ActionController`).
7. **ActionController**: Player input processing.
8. **CombatController**: Combat state machine.
9. **AspectController**: Aspect ability input.
10. **InventoryController**: UI interactions for items.
11. **ProgressionController**: Resonance HUD & Discipline selection.
12. **PlayerHUDController**: Core UI updates.
13. **CombatFeedbackUI**: Visual hit/damage feedback.
14. **HeavenEnvironmentController**: Ethereal plane VFX/Environment configuration.
*Note: Any remaining controllers load alphabetically after this list.*

---

## Guidelines for Preventing Circular Dependencies
1. **Never** `require` another Service/Controller directly at the top level of a module.
2. **Inject dependencies** via the `Init` phase or `require` inside methods (lazy loading).
3. Complex cyclic data flows should be refactored into independent provider modules or handled through an Event/Signal bus.