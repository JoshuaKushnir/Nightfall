# Nightfall: Engineering Manifesto & Architecture Rules

## 1. System Memory & Session Tracking
- **Session Log:** Before every task, READ `docs/session-log.md`. After every task, UPDATE it with completed work, new types created, and pending technical debt.
- **Context Preservation:** Always reference `src/shared/types` to ensure data structures remain consistent across the server/client boundary.

## 2. Modular Architecture (Rojo/Luau)
- **Service/Controller Pattern:** - Server logic lives in `src/server/services`. 
    - Client logic lives in `src/client/controllers`.
    - No direct cross-talk; use `src/shared/network` for Remote communication.
- **Dependency Injection:** Services must be initialized via an `Init` or `Start` method. Do not use `wait()` for loading; use a signal-based provider.
- **DRY Utility First:** If logic is used twice (e.g., Magnitude checks, Raycasts), it MUST move to `src/shared/modules/Utils`.

## 3. Combat & Gameplay Logic
- **State-Machine Authoritative:** Every character (NPC/Player) must have a `State` entry in the `StateService`. 
- **Action Validation:** - `if State == "Stunned" then return`
    - `if State == "Attacking" then return`
- **Mantra Framework:** Mantras are modular objects. A Mantra must contain: `BaseDamage`, `CastTime`, `Cooldown`, and a `VFX_Function`.

## 4. Coding Standards
- **Typing:** Strict typing mandatory (`--!strict`). Use `export type` for all data schemas.
- **Composition:** Avoid large "Player" classes. Use a `Component` system for attributes like `Health`, `Mana`, and `Posture`.
- **Boilerplate:** Every new module must include the standard documentation header (Class, Description, Dependencies).

# docs/session-log.md (The Memory File)
Always update this file so you remember what you've built.