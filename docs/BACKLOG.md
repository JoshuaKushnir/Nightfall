# Nightfall: Development Backlog
**Project:** Nightfall/Nightbound - Dark Fantasy Roblox RPG  
**Architecture:** Rojo + Luau (Strict Typing, DRY, Modular)  
**Goal:** Published MVP with Combat, Magic (Mantras), and Narrative Systems

---

## 📋 Backlog Overview
This document tracks all development work from infrastructure to deployment. Each Phase builds upon the previous, maintaining strict architectural standards and type safety.

**Progress Tracking:**
- ✅ Phase 0: Genesis (Complete - NF-001)
- 🔄 Phase 1: Core Framework (In Planning)
- ⏳ Phase 2-5: Pending

---

## Phase 0: Genesis ✅
**Status:** Complete (Session NF-001)  
**Completed:**
- Repository structure with Rojo configuration
- `StateService` (The Nexus) for player state management
- `PlayerData` types with strict typing
- Git repository initialized and committed

---

## Phase 1: The Core Framework (Infrastructure)
**Goal:** Establish the foundational systems required for all gameplay features.

### Issue #2: ProfileService Data Wrapper
**Title:** Implement ProfileService Wrapper for Player Data Persistence  
**Labels:** `phase-1`, `infrastructure`, `data`, `critical`

**Description:**
Create a robust data management service that wraps ProfileService to handle player data loading, saving, and session management. This service must integrate with the existing `StateService` and `PlayerData` types.

**Technical Requirements:**
- Create `src/server/services/DataService.lua` with strict typing
- Implement ProfileService integration with proper error handling
- Support for data versioning and migration (future-proofing)
- Auto-save functionality on player leave
- Session locking to prevent duplication exploits
- Reconcile data with `PlayerData` type from `src/shared/types/PlayerData.lua`
- Include methods:
  - `LoadProfile(player: Player): PlayerData?`
  - `SaveProfile(player: Player): boolean`
  - `GetProfile(player: Player): PlayerData?`
  - `ReleaseProfile(player: Player): ()`
- Handle edge cases: server shutdown, player rejoin, data corruption
- Add DataStore fail-safes (retry logic, exponential backoff)

**Dependencies:**
- ProfileService module (external)
- `PlayerData` types
- `StateService` integration

**Acceptance Criteria:**
- [ ] Player data loads on join and saves on leave
- [ ] No data loss during normal operations
- [ ] Session locking prevents duplication
- [ ] Graceful handling of DataStore failures
- [ ] Integration test with StateService

---

### Issue #3: Enhanced State Machine System
**Title:** Expand StateService with State Transition Validation  
**Labels:** `phase-1`, `infrastructure`, `state-machine`, `high`

**Description:**
Enhance the existing `StateService` to include state transition validation, state history tracking, and signal-based state change notifications. This creates the authoritative state system for all gameplay actions.

**Technical Requirements:**
- Extend `src/shared/modules/StateService.lua`
- Implement state transition validation matrix:
  - Define legal transitions (e.g., Can't go from Dead → Attacking)
  - Block illegal transitions with warning messages
- Add state history tracking (last 5 states with timestamps)
- Create signal-based notification system:
  - `StateChanged: RBXScriptSignal<Player, OldState, NewState>`
- Add methods:
  - `CanTransitionTo(player: Player, newState: PlayerState): boolean`
  - `GetStateHistory(player: Player): StateHistory[]`
  - `ForceState(player: Player, state: PlayerState): ()` (admin only)
- Add state duration tracking for analytics
- Implement state timeout system (e.g., Stunned automatically expires)

**Dependencies:**
- Existing `StateService`
- Signal library (GoodSignal or BindableEvent wrapper)

**Acceptance Criteria:**
- [ ] Invalid state transitions are blocked
- [ ] State changes emit signals that other systems can listen to
- [ ] State history is tracked and accessible
- [ ] Automated state expiration works correctly

---

### Issue #4: Network Provider (Centralized RemoteEvent Handling)
**Title:** Create Centralized Network Communication Provider  
**Labels:** `phase-1`, `infrastructure`, `networking`, `critical`

**Description:**
Build a type-safe, centralized network communication system that handles all client-server interactions. This eliminates scattered RemoteEvents and provides a single interface for network calls.

**Technical Requirements:**
- Create `src/shared/network/NetworkProvider.lua`
- Create `src/shared/types/NetworkTypes.lua` for packet definitions
- Define network event registry (enum-based):
  ```lua
  export type NetworkEvent =
    "CombatAction" | "MantraCast" | "StateUpdate" | 
    "DialogueChoice" | "ItemInteraction"
  ```
- Server-side (`src/server/services/NetworkService.lua`):
  - Register event handlers with type checking
  - Rate limiting per player per event
  - Validation middleware (sanity checks on client data)
  - Logging for suspicious activity
- Client-side (`src/client/controllers/NetworkController.lua`):
  - Type-safe event firing
  - Response promise support
  - Connection retry logic
- Create RemoteEvent/RemoteFunction containers in `src/shared/network/`
- Implement middleware system for:
  - Authentication (is player instance valid?)
  - Authorization (can player perform this action?)
  - Sanitization (clean user input)

**Dependencies:**
- None (foundational system)

**Acceptance Criteria:**
- [ ] All network calls go through NetworkProvider
- [ ] Type safety enforced on both client and server
- [ ] Rate limiting prevents spam exploits
- [ ] Easy to add new network events
- [ ] Comprehensive logging for debugging

---

### Issue #5: Server & Client Bootstrap Systems
**Title:** Implement Runtime Initialization for Server and Client  
**Labels:** `phase-1`, `infrastructure`, `initialization`, `high`

**Description:**
Create the initialization sequences that load all services and controllers in the correct order with proper dependency resolution.

**Technical Requirements:**
- Server Bootstrap (`src/server/runtime/init.lua`):
  - Load all services from `src/server/services/`
  - Call `Init()` on all services (dependency setup)
  - Call `Start()` on all services (begin operations)
  - Handle initialization errors gracefully
  - Log initialization sequence
- Client Bootstrap (`src/client/runtime/init.lua`):
  - Wait for player character to load
  - Load all controllers from `src/client/controllers/`
  - Initialize controllers in dependency order
  - Connect to NetworkController
- Create `src/shared/modules/Loader.lua` utility:
  - `LoadModules(folder: Instance): {[string]: ModuleScript}`
  - Alphabetical loading order (predictable)
- Add startup profiling (track initialization time)
- Implement hot-reload support for development

**Dependencies:**
- Services/Controllers from other issues

**Acceptance Criteria:**
- [ ] Server initializes all services without errors
- [ ] Client waits for server readiness
- [ ] Initialization order is deterministic
- [ ] Clear error messages for initialization failures
- [ ] Hot-reload works in Studio

---

## Phase 2: Combat & Fluidity (The Feel)
**Goal:** Create responsive, satisfying combat with hitboxes, animations, and timing-based mechanics.

### Issue #6: Modular Hitbox System
**Title:** Implement Raycast-Based, Weapon-Agnostic Hitbox System  
**Labels:** `phase-2`, `combat`, `hitbox`, `critical`

**Description:**
Create a flexible hitbox system that works with any weapon type (swords, fists, magic projectiles) using raycasting and spatial queries.

**Technical Requirements:**
- Create `src/shared/modules/HitboxService.lua`
- Create `src/shared/types/HitboxTypes.lua`:
  ```lua
  export type HitboxShape = "Box" | "Sphere" | "Raycast"
  export type HitboxConfig = {
    Shape: HitboxShape,
    Size: Vector3,
    Offset: CFrame,
    Duration: number,
    Blacklist: {Instance},
  }
  export type HitResult = {
    Hit: boolean,
    Instances: {Instance},
    Positions: {Vector3},
  }
  ```
- Implement hitbox shapes:
  - **Box:** Region3-based or spatial query
  - **Sphere:** Magnitude checks with radius
  - **Raycast:** Directional ray with length
- Server-authoritative hit detection (client predicts, server validates)
- Blacklist system (don't hit teammates, don't hit twice)
- Hitbox visualization in Studio (debug mode)
- Performance optimization (spatial partitioning, early exits)
- Integration with `StateService` (can't hit while stunned)

**Dependencies:**
- `StateService`
- `NetworkProvider` (for client → server hit reporting)

**Acceptance Criteria:**
- [ ] Weapon swings detect hits accurately
- [ ] No double-hits on same target
- [ ] Server-authoritative validation prevents exploits
- [ ] Debug visualization helps with tuning
- [ ] Performs well with multiple hitboxes active

---

### Issue #7: Action Controller (Animation & Feel)
**Title:** Create Action Controller for Animation Syncing and Game Feel  
**Labels:** `phase-2`, `combat`, `animation`, `high`

**Description:**
Build the system that synchronizes animations, hit-stop, camera shake, and other "game feel" elements during combat actions.

**Technical Requirements:**
- Create `src/client/controllers/ActionController.lua`
- Create `src/shared/types/ActionTypes.lua`:
  ```lua
  export type ActionConfig = {
    AnimationId: string,
    HitStop: number, -- freeze frames on hit
    CameraShake: CameraShakeConfig?,
    SoundEffect: string?,
    VFX: (character: Model) -> ()?,
  }
  ```
- Implement animation queueing (can't interrupt certain actions)
- Hit-stop effect (brief time slow/freeze on successful hit)
- Camera shake integration (trauma-based system)
- Sound effect playback synchronized with animation events
- VFX spawning at animation markers
- Server-authoritative action validation (prevent animation spoofing)
- Client-side prediction for responsiveness
- Rollback system if server rejects action

**Dependencies:**
- `NetworkProvider`
- `StateService`
- `HitboxService`

**Acceptance Criteria:**
- [ ] Animations play smoothly and sync with hits
- [ ] Hit-stop makes combat feel impactful
- [ ] Camera shake enhances action without being excessive
- [ ] No animation desync between client and server
- [ ] Actions can be canceled or queued appropriately

---

### Issue #8: Parrying & Block Mechanics
**Title:** Implement Timing-Based Parry and Block System  
**Labels:** `phase-2`, `combat`, `mechanics`, `high`

**Description:**
Create a skill-based defensive system where players can block attacks or parry with precise timing for counterattack opportunities.

**Technical Requirements:**
- Extend `PlayerData` with defense states:
  ```lua
  export type DefenseState = {
    Blocking: boolean,
    ParryWindow: boolean,
    ParryWindowStart: number,
    ParryWindowDuration: number, -- e.g., 0.2 seconds
  }
  ```
- Create `src/server/services/DefenseService.lua`:
  - `StartBlock(player: Player): boolean`
  - `ReleaseBlock(player: Player): ()`
  - `AttemptParry(player: Player): boolean`
  - `CheckParryTiming(attacker: Player, defender: Player): boolean`
- Block mechanics:
  - Reduces damage by percentage (e.g., 50% reduction)
  - Drains Posture on blocked hits
  - Movement speed reduced while blocking
- Parry mechanics:
  - Tight timing window (0.2s default)
  - Full damage negation on successful parry
  - Attacker enters "Stunned" state briefly
  - Defender gets attack opportunity
- Integration with `HitboxService` for parry detection
- Visual/audio feedback for successful parries
- Balance tuning: parry window duration configurable

**Dependencies:**
- `StateService`
- `HitboxService`
- `ActionController`

**Acceptance Criteria:**
- [ ] Blocking reduces incoming damage
- [ ] Parrying requires precise timing
- [ ] Successful parries stun the attacker
- [ ] Visual and audio feedback is clear
- [ ] Balance feels fair and skill-based

---

## Phase 3: The Mantra System (Magic)
**Goal:** Implement the modular magic system with elements, classes, and resource management.

### Issue #9: Dynamic Mantra Loader
**Title:** Create Folder-Based Mantra Module Loading System  
**Labels:** `phase-3`, `mantras`, `magic`, `critical`

**Description:**
Build a system that dynamically loads Mantra definitions from a folder structure, allowing easy addition of new spells without code changes.

**Technical Requirements:**
- Create folder structure:
  ```
  src/shared/mantras/
    Fire/
      Fireball.lua
      FlameWave.lua
    Ice/
      IceShard.lua
    Lightning/
      Bolt.lua
  ```
- Create `src/shared/modules/MantraLoader.lua`:
  - Recursively scan `mantras/` folder
  - Load all mantra modules
  - Validate mantra schema against `Mantra` type
  - Register mantras in central registry
  - Support hot-reloading in Studio
- Each Mantra module exports:
  ```lua
  return {
    Name = "Fireball",
    Element = "Fire",
    BaseDamage = 25,
    CastTime = 0.8,
    Cooldown = 3.0,
    ManaCost = 20,
    Requirements = {
      Level = 5,
      Stats = { Intelligence = 15 }
    },
    VFX_Function = function(player, target) ... end,
    OnCast = function(caster, target) ... end,
  }
  ```
- Create `src/server/services/MantraService.lua`:
  - `GetMantraById(id: string): Mantra?`
  - `GetMantrasByElement(element: string): {Mantra}`
  - `PlayerMeetsRequirements(player: Player, mantra: Mantra): boolean`

**Dependencies:**
- `PlayerData` types
- `Loader` utility

**Acceptance Criteria:**
- [ ] Mantras load automatically from folder structure
- [ ] New mantras can be added without code changes
- [ ] Invalid mantra definitions are rejected with clear errors
- [ ] Hot-reloading works in Studio

---

### Issue #10: Multi-Element/Class Logic & Requirements
**Title:** Implement Class System with Element Affinities and Requirement Checks  
**Labels:** `phase-3`, `mantras`, `progression`, `high`

**Description:**
Create the class and element system that determines which mantras a player can use based on their stats, level, and chosen class.

**Technical Requirements:**
- Extend `PlayerData` with class information:
  ```lua
  export type PlayerClass = "Warrior" | "Mage" | "Rogue" | "Cleric"
  export type ElementAffinity = {
    Fire: number,
    Ice: number,
    Lightning: number,
    Wind: number,
  }
  ```
- Create `src/shared/types/ClassTypes.lua`:
  - Define class stat modifiers
  - Define element affinity bonuses
  - Define class-specific restrictions
- Create `src/server/services/ClassService.lua`:
  - `SetPlayerClass(player: Player, class: PlayerClass): boolean`
  - `GetElementAffinity(player: Player, element: string): number`
  - `CanUseMantra(player: Player, mantra: Mantra): boolean`
- Requirement checking:
  - Level requirements
  - Stat requirements (Intelligence, Strength, etc.)
  - Class restrictions (Warrior can't use Mage mantras)
  - Element affinity (affects damage/effect)
- Class selection UI (client-side)
- Stat allocation on level up

**Dependencies:**
- `MantraLoader`
- `DataService`
- `PlayerData` types

**Acceptance Criteria:**
- [ ] Players can choose a class
- [ ] Class affects available mantras and stats
- [ ] Requirement checks prevent invalid mantra usage
- [ ] Element affinity modifies mantra effectiveness

---

### Issue #11: Global Cooldown & Mana (Posture) Management
**Title:** Implement Cooldown Tracking and Resource Management System  
**Labels:** `phase-3`, `mantras`, `resources`, `high`

**Description:**
Create the system that tracks mantra cooldowns, manages mana/posture resources, and enforces casting restrictions.

**Technical Requirements:**
- Extend `PlayerData.ActiveCooldowns` usage in `StateService`
- Create `src/shared/modules/ResourceManager.lua`:
  - `ConsumeMana(player: Player, amount: number): boolean`
  - `RegenerateMana(player: Player, deltaTime: number): ()`
  - `HasSufficientMana(player: Player, cost: number): boolean`
  - `DamagePosture(player: Player, amount: number): ()`
  - `IsPostureBroken(player: Player): boolean`
  - `StartCooldown(player: Player, mantraName: string, duration: number): ()`
  - `IsOnCooldown(player: Player, mantraName: string): boolean`
  - `GetRemainingCooldown(player: Player, mantraName: string): number`
- Mana regeneration (per-frame update):
  - Base regeneration rate from `ManaComponent`
  - Paused during casting or combat
  - Bonus from equipment/buffs
- Posture system:
  - Drained by blocking/taking hits
  - Regenerates when not blocking
  - Breaks at 0, causing Stunned state
- Global cooldown (GCD):
  - Brief lockout after any action (0.1-0.5s)
  - Prevents ability spam
- UI synchronization (client displays cooldowns/resources)

**Dependencies:**
- `StateService`
- `MantraService`
- `NetworkProvider`

**Acceptance Criteria:**
- [ ] Mantra cooldowns are tracked accurately
- [ ] Mana consumption and regeneration work correctly
- [ ] Posture breaking causes appropriate stun
- [ ] Global cooldown prevents ability spam
- [ ] UI displays resources and cooldowns in real-time

---

## Phase 4: World & Narrative (The RPG)
**Goal:** Add progression, dialogue, and RPG systems that give the game depth and replayability.

### Issue #12: Branching Dialogue System
**Title:** Create Flag-Based Branching Dialogue System  
**Labels:** `phase-4`, `narrative`, `dialogue`, `high`

**Description:**
Implement a dialogue system that supports branching conversations, story flags, and choice-based progression.

**Technical Requirements:**
- Create `src/shared/types/DialogueTypes.lua`:
  ```lua
  export type DialogueNode = {
    Id: string,
    Speaker: string,
    Text: string,
    Choices: {DialogueChoice},
    Requirements: {[string]: boolean}, -- story flags
    OnComplete: (player: Player) -> (),
  }
  export type DialogueChoice = {
    Text: string,
    NextNodeId: string,
    FlagsToSet: {[string]: boolean},
  }
  ```
- Create `src/server/services/DialogueService.lua`:
  - `StartDialogue(player: Player, npcId: string): DialogueNode`
  - `MakeChoice(player: Player, choiceIndex: number): DialogueNode?`
  - `SetStoryFlag(player: Player, flag: string, value: boolean): ()`
  - `HasStoryFlag(player: Player, flag: string): boolean`
- Create `src/client/controllers/DialogueController.lua`:
  - UI rendering for dialogue boxes
  - Choice button generation
  - Text animations (typewriter effect)
- Dialogue data storage (JSON or Lua modules)
- Story flag persistence (integrated with DataService)
- Support for conditional dialogue (different responses based on flags)
- NPC interaction proximity detection

**Dependencies:**
- `DataService` (for flag persistence)
- `NetworkProvider`

**Acceptance Criteria:**
- [ ] Players can interact with NPCs to start dialogues
- [ ] Choices affect future dialogue options
- [ ] Story flags are saved and loaded correctly
- [ ] Dialogue UI is clear and polished
- [ ] System supports complex branching narratives

---

### Issue #13: Progression & Leveling System
**Title:** Implement Experience, Leveling, and Stat Scaling System  
**Labels:** `phase-4`, `progression`, `rpg`, `critical`

**Description:**
Create the core progression system where players gain experience, level up, and allocate stat points.

**Technical Requirements:**
- Extend `PlayerData` with progression data:
  ```lua
  export type ProgressionData = {
    Level: number,
    Experience: number,
    ExperienceToNextLevel: number,
    StatPoints: number,
    AllocatedStats: {
      Strength: number,
      Intelligence: number,
      Dexterity: number,
      Vitality: number,
    }
  }
  ```
- Create `src/server/services/ProgressionService.lua`:
  - `AwardExperience(player: Player, amount: number): ()`
  - `LevelUp(player: Player): ()`
  - `AllocateStatPoint(player: Player, stat: string): boolean`
  - `CalculateExperienceRequired(level: number): number`
  - `GetScaledStat(player: Player, stat: string): number`
- Experience sources:
  - Combat (defeating enemies)
  - Quest completion
  - Exploration (discovering locations)
- Leveling formula:
  - Exponential scaling (e.g., XP = 100 * level^1.5)
  - Configurable via constants
- Stat allocation:
  - Gain stat points on level up
  - Each stat affects different mechanics:
    - Strength → Physical damage, carry weight
    - Intelligence → Mantra damage, mana pool
    - Dexterity → Parry window, dodge
    - Vitality → Health, posture
  - Soft caps on stat values
- Level-up effects:
  - Visual/audio celebration
  - Stat restoration (full health/mana)
  - Notification of unlocked mantras/abilities

**Dependencies:**
- `DataService`
- `StateService`
- `ClassService`

**Acceptance Criteria:**
- [ ] Players gain experience from various sources
- [ ] Leveling up awards stat points
- [ ] Stats can be allocated and affect gameplay
- [ ] Experience requirements scale appropriately
- [ ] Level-up feels rewarding

---

### Issue #14: Armor/Class Component System
**Title:** Create Modular Armor and Equipment System with Visual & Stat Effects  
**Labels:** `phase-4`, `equipment`, `systems`, `high`

**Description:**
Implement an equipment system where armor pieces provide stat bonuses and change character appearance.

**Technical Requirements:**
- Create `src/shared/types/EquipmentTypes.lua`:
  ```lua
  export type EquipmentSlot = "Helmet" | "Chestplate" | "Gauntlets" | "Boots" | "Weapon"
  export type ArmorPiece = {
    Id: string,
    Name: string,
    Slot: EquipmentSlot,
    ModelId: string, -- Asset ID for 3D model
    StatBonuses: {
      Health: number?,
      Mana: number?,
      Defense: number?,
      -- etc.
    },
    Requirements: {
      Level: number?,
      Class: PlayerClass?,
    },
  }
  export type Loadout = {
    [EquipmentSlot]: ArmorPiece?,
  }
  ```
- Create `src/server/services/EquipmentService.lua`:
  - `EquipArmor(player: Player, armorId: string): boolean`
  - `UnequipSlot(player: Player, slot: EquipmentSlot): boolean`
  - `GetLoadout(player: Player): Loadout`
  - `CalculateTotalStats(player: Player): StatsTable`
  - `ValidateEquipment(player: Player, armor: ArmorPiece): boolean`
- Visual equipment system:
  - Dynamically attach armor models to character
  - Handle R15 and R6 rig compatibility
  - Layer equipment properly (no clipping)
- Stat calculation:
  - Base stats from level/class
  - Equipment bonuses added on top
  - Update health/mana maximums when equipment changes
- Inventory system (basic):
  - Store unequipped armor pieces
  - Pickup/drop functionality
- Equipment set bonuses (future enhancement)

**Dependencies:**
- `DataService`
- `ProgressionService`
- `ClassService`

**Acceptance Criteria:**
- [ ] Players can equip and unequip armor
- [ ] Equipped armor is visible on character
- [ ] Stat bonuses are applied correctly
- [ ] Equipment requirements are enforced
- [ ] Inventory tracks owned equipment

---

## Phase 5: Polish & Deployment (The Launch)
**Goal:** Optimize, secure, and prepare the game for public release with analytics and fail-safes.

### Issue #15: DataStore Fail-Safes & Analytics
**Title:** Implement Advanced DataStore Protection and Analytics Tracking  
**Labels:** `phase-5`, `data`, `analytics`, `critical`

**Description:**
Add comprehensive error handling, backup systems, and analytics to ensure data integrity and track player behavior.

**Technical Requirements:**
- Enhance `DataService` with fail-safes:
  - Retry logic with exponential backoff
  - Local session backups (in-memory)
  - Periodic auto-saves (every 5 minutes)
  - Graceful degradation (read-only mode if saves fail)
  - Data reconciliation (merge local and remote changes)
  - Corruption detection (schema validation)
- Create `src/server/services/AnalyticsService.lua`:
  - Track player events:
    - Login/logout times
    - Level progression
    - Mantra usage frequency
    - Combat encounters (wins/losses)
    - Playtime per session
  - Send to external analytics (e.g., Google Analytics, custom endpoint)
  - GDPR compliance (opt-out option)
- Create admin dashboard data:
  - Active player count
  - Average session length
  - Popular mantras/equipment
  - Economy metrics (if applicable)
- Error logging and reporting:
  - Capture errors with stack traces
  - Send to external logging service (e.g., Sentry)
  - Rate limit error reports

**Dependencies:**
- `DataService`
- `NetworkProvider`

**Acceptance Criteria:**
- [ ] Data loss is prevented even during server crashes
- [ ] Analytics track player behavior without impacting performance
- [ ] Error logs provide actionable debugging information
- [ ] Admin dashboard displays meaningful metrics
- [ ] GDPR compliance mechanisms are in place

---

### Issue #16: Performance Optimization & Memory Management
**Title:** Optimize Game Performance and Prevent Memory Leaks  
**Labels:** `phase-5`, `optimization`, `performance`, `critical`

**Description:**
Profile and optimize the game to ensure smooth performance across all devices, with special attention to memory management and streaming compatibility.

**Technical Requirements:**
- Profiling and benchmarking:
  - Use Roblox's MicroProfiler and Developer Console
  - Identify performance bottlenecks (CPU and memory)
  - Set performance budgets (target 60 FPS on low-end devices)
- Memory optimization:
  - Audit for memory leaks (uncollected connections, cached instances)
  - Implement proper cleanup in all services (Destroy method)
  - Use weak tables for caches where appropriate
  - Profile memory usage over time
- CPU optimization:
  - Minimize `RenderStepped`/`Heartbeat` connections
  - Batch operations where possible
  - Use spatial partitioning for large-scale checks
  - Optimize hitbox detection (early exits)
- Network optimization:
  - Compress network packets
  - Send only necessary data to clients
  - Throttle non-critical updates (e.g., UI refreshes)
- Streaming-enabled compatibility:
  - Test with StreamingEnabled on
  - Handle models loading/unloading gracefully
  - Request streaming radius for critical areas
- Asset optimization:
  - Compress textures
  - Use LOD (Level of Detail) models
  - Remove unused assets
- Create `src/shared/modules/PerformanceMonitor.lua`:
  - Track FPS, memory, and network usage
  - Auto-report performance issues to server

**Dependencies:**
- All existing systems

**Acceptance Criteria:**
- [ ] Game runs at 60 FPS on target devices
- [ ] No memory leaks detected over long play sessions
- [ ] StreamingEnabled compatibility verified
- [ ] Network bandwidth is optimized
- [ ] Performance metrics are tracked and logged

---

### Issue #17: UI/UX Responsive Framework
**Title:** Create Modular, Responsive UI Framework (Roact/Fusion Style)  
**Labels:** `phase-5`, `ui`, `ux`, `high`

**Description:**
Build a comprehensive UI system that is responsive, accessible, and modular, supporting all game features with a consistent design language.

**Technical Requirements:**
- Choose UI framework:
  - Option A: Fusion (reactive state management)
  - Option B: Roact (React-like components)
  - Option C: Pure ScreenGui (lightweight)
- Create `src/client/controllers/UIController.lua`:
  - Manages all UI screens (inventory, dialogue, combat HUD)
  - Handles screen transitions
  - Responsive scaling (different screen sizes/ratios)
- Design system components:
  - Button (standard, disabled, hover states)
  - Text label (headers, body, tooltips)
  - Input field (text entry)
  - Progress bar (health, mana, cooldowns)
  - Modal dialogs (confirmations, errors)
  - Inventory grid
- Implement responsive scaling:
  - Use UDim2 with scale values
  - Test on multiple aspect ratios (4:3, 16:9, 21:9)
  - Mobile compatibility (larger touch targets)
- Accessibility features:
  - Controller support (gamepad navigation)
  - Adjustable text size
  - Colorblind modes (optional)
- Combat HUD:
  - Health/Mana/Posture bars
  - Equipped mantras with cooldowns
  - Status effects display
  - Target info (if applicable)
- Menus:
  - Inventory/Equipment
  - Character stats
  - Settings
- Animation and polish:
  - Smooth transitions (tweening)
  - Visual feedback on interactions
  - Consistent design language

**Dependencies:**
- `NetworkProvider`
- All gameplay systems (displays their state)

**Acceptance Criteria:**
- [ ] UI is responsive across all screen sizes
- [ ] All game features have polished UI
- [ ] UI components are reusable and modular
- [ ] Controller/gamepad support works
- [ ] UI feels professional and consistent

---

### Issue #18: Testing & QA Framework
**Title:** Establish Testing Framework and QA Procedures  
**Labels:** `phase-5`, `testing`, `qa`, `medium`

**Description:**
Create a testing framework and QA checklist to ensure the game is stable and bug-free before launch.

**Technical Requirements:**
- Unit testing framework:
  - Use TestEZ or similar Roblox testing library
  - Write unit tests for critical systems:
    - StateService state transitions
    - DataService save/load
    - MantraLoader validation
    - HitboxService detection
  - Automate test running in Studio
- Integration testing:
  - Test full gameplay loops (login → combat → save → logout)
  - Test multiplayer scenarios (multiple players interacting)
  - Test edge cases (network lag, data corruption)
- QA checklist (`docs/QA_CHECKLIST.md`):
  - Gameplay tests (combat, progression, dialogue)
  - Bug tests (known issues verified fixed)
  - Performance tests (FPS, memory, network)
  - Compatibility tests (devices, streaming)
- Beta testing:
  - Private server for beta testers
  - Feedback collection system
  - Bug reporting UI in-game
- Regression testing:
  - Re-test fixed bugs to ensure no regressions
  - Maintain test suite for continuous integration

**Dependencies:**
- All systems

**Acceptance Criteria:**
- [ ] Unit tests cover critical systems
- [ ] Integration tests verify full gameplay loops
- [ ] QA checklist is complete and verified
- [ ] Beta testing provides actionable feedback
- [ ] No critical bugs remain

---

### Issue #19: Launch Preparation & Deployment
**Title:** Final Launch Checklist and Deployment to Production  
**Labels:** `phase-5`, `deployment`, `launch`, `critical`

**Description:**
Complete all final preparations for public launch, including game description, thumbnails, and monitoring systems.

**Technical Requirements:**
- Pre-launch checklist:
  - [ ] All Phase 5 issues completed
  - [ ] QA testing passed
  - [ ] Performance targets met
  - [ ] DataStore systems verified in production
  - [ ] Analytics tracking operational
  - [ ] Admin tools functional
- Game page setup:
  - Write compelling game description
  - Create high-quality thumbnail (1920x1080)
  - Add game icons (512x512)
  - Set up social media links
  - Add tags and categories
- Monetization (if applicable):
  - Game passes designed and implemented
  - Developer products (currency, boosts)
  - Premium benefits configured
- Launch monitoring:
  - Real-time player count tracking
  - Error rate monitoring
  - Server performance dashboard
  - Hotfix deployment plan
- Post-launch support:
  - Community management (Discord, DevForum)
  - Bug triage process
  - Content update roadmap
- Documentation:
  - Player guide (how to play)
  - Developer documentation (for future updates)
  - API reference (for contributors)

**Dependencies:**
- All previous issues

**Acceptance Criteria:**
- [ ] Game is published and accessible
- [ ] Game page is polished and appealing
- [ ] Monitoring systems are active
- [ ] Launch goes smoothly with no critical issues
- [ ] Post-launch support plan is in place

---

## Additional Considerations

### Technical Debt Tracking
As development progresses, track technical debt in `docs/session-log.md`:
- Temporary hacks or workarounds
- Code that needs refactoring
- Performance bottlenecks to address later
- Features that were cut or simplified

### Code Review Standards
- All code must pass strict Luau type checking (`--!strict`)
- Follow DRY principle (no copy-pasted code)
- Module documentation headers required
- Peer review before merging major features

### Version Control
- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`
- Branch strategy: `main` for stable, `dev` for active work, feature branches for issues
- Tag releases: `v0.1.0-alpha`, `v1.0.0` (MVP launch)

### Continuous Integration
- Automated testing on commits (TestEZ)
- Rojo sync verification
- Lint checks (Selene or similar)
- Performance benchmarking

---

## MVP Definition
**Minimum Viable Product includes:**
- ✅ Player data persistence (ProfileService)
- ✅ Basic combat (hitboxes, animations, parrying)
- ✅ 5-10 starter mantras (magic spells)
- ✅ Character progression (leveling, stat allocation)
- ✅ Simple equipment system (3-5 armor sets)
- ✅ Basic dialogue with 1-2 NPCs
- ✅ Polished UI and responsive feel
- ✅ Performance optimization (60 FPS target)
- ✅ Stable DataStore with fail-safes

**Post-MVP (Future Updates):**
- Advanced PvP arenas
- Guild/clan system
- World bosses and raids
- Expanded narrative (quest chains)
- Crafting and economy
- Seasonal events

---

**End of Backlog**  
**Last Updated:** Session NF-002 | February 12, 2026

This backlog represents the complete path from current state (Genesis) to a publishable MVP. Each issue is designed to be self-contained, testable, and aligned with the Nightfall engineering standards.
