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

## 5. Issue Management & Dependencies
- **Issue Linking:** Use GitHub's "Linked Issues" feature (not manual text in description) to mark issue dependencies.
  - **How to Link Issues:**
    1. Open the issue on GitHub web
    2. Scroll to "Linked issues" section (right sidebar)
    3. Click "Add linked issue"
    4. Select relationship type: **"blocks"** (this issue blocks another) or **"blocked by"** (this issue is blocked by another)
    5. Enter the issue number to link
  - **When to Use:**
    - Use `blocks` when your issue must be completed before another can start
    - Use `blocked by` when your issue depends on another issue being completed first
  - **Dependency Format:** Use `Requires #24` or similar in description ONLY for documentation/clarity. Always back it up with actual Linked Issues.
  - **Removal:** Remove manual "Requires" text from descriptions once linked issues are created via GitHub UI.

# docs/session-log.md (The Memory File)
Always update this file so you remember what you've built.