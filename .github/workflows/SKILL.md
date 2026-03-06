# Skill: Nightbound Polishing & Ability Implementation (Luau/Rojo)

A specialized workflow for the `Nightbound` (Roblox/Luau) project to handle the transition from placeholder ability stubs to high-quality, physical, server-authoritative combat modules. Use this when the user asks to "polish", "finalize", or "implement" specific Aspect moves (Ash, Tide, Ember, Gale, Void).

## Prerequisites
- [ ] Read [docs/session-log.md](docs/session-log.md) to identify the current "physicality" status of systems (e.g., HitboxService vs legacy math).
- [ ] Verify `--!strict` is at the top of all target files.
- [ ] Identify which GitHub Issue (#XX) this polish belongs to.

## Step-by-Step Workflow

### 1. Registry & Type Validation
- Ensure the ability is correctly defined in [src/shared/types/AspectTypes.lua](src/shared/types/AspectTypes.lua).
- Verify the move is registered in its corresponding Aspect file (e.g., `Ash.lua`) under the `Moves` table and follows the `AspectMoveset` structure.
- Check [src/shared/modules/AbilityRegistry.lua](src/shared/modules/AbilityRegistry.lua) if the move isn't showing up in-game (G-key debug cycle).

### 2. Physicalization (Server-Side)
- **Replace Dummy Logic:** Locate use of `SetAttribute("IncomingPostureDamage", N)` or raw `Distance` checks.
- **Implement Hitbox:** Use [src/shared/modules/HitboxService.lua](src/shared/modules/HitboxService.lua) to create a spatial query (`GetPartBoundsInRadius`, `Blockcast`).
- **State Validation:** Call [src/shared/modules/StateService.lua](src/shared/modules/StateService.lua) before execution to prevent casting while Stunned/Dead.
- **Damage/Posture:**
  - Call `PostureService:DrainPosture(target, amount)` for posture damage.
  - Call `CombatService:ApplyDamage(caster, target, amount)` for HP damage.

### 3. Visuals & Networking
- **VFX Stubs:** Create local VFX functions with the name `_VFX_[AbilityName]_[Phase]`. 
  - *Rule:* Programmer creates the hook/logic; Animator/VFX artist fills the stub later.
  - *Example:* `local function _VFX_AshenStep_DashTrail(player, origin, destination) end`
- **Network Handlers:** Ensure `NetworkProvider` is used to notify clients for any feedback (Screen flashes, UI prompts).

### 4. Testing & Verification
- **Unit Tests:** Check if a corresponding test exists in `tests/unit/`. If missing, create one.
- **Studio Run:**
  - Verify zero warnings in the Output panel.
  - Check the G-key DebugInput to ensure the ability cycles and activates.
  - Validate State transitions (e.g., "Casting" state is set and cleared).

## Quality Criteria (Acceptance)
- [ ] No `wait()`—only `task.wait()` or `task.delay()`.
- [ ] All functions typed (parameters and returns).
- [ ] Private fields prefixed with `_`.
- [ ] Server validates all inputs (CFrame/Position) from the client.
- [ ] Commit message references the Issue ID: `<type>(#XX): Polish [Ability] with HitboxService`.

## Example Prompts
- "Polish the Ember Depth 1 abilities using the new HitboxService."
- "Implement the real behavior for Gale's WindStrike move, ensuring it launches the target."
- "Refactor Void's Blink to use Server-validated position gating."
