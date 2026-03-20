# Implementation Plan for Nightfall MVP

## Overview
Nightfall is a Roblox RPG with client-server architecture using Luau. The codebase is well-structured with client controllers, server services, shared modules/types, and comprehensive unit tests. Current state shows advanced features (movement, combat, inventory, progression, abilities) but needs polish for MVP: HUD consistency, error fixes, menu integration, and GitHub issue management.

Goal: Reach MVP by completing GitHub Issue #183 (HUD revamp) and related blockers, then close issues systematically using GitHub CLI. MVP defined as: playable Ring-1 zone with core loop (combat, progression, inventory, movement) without crashes.

## Types
No new types needed. Existing NetworkTypes.lua, ProgressionTypes.lua sufficient. Add HUD-related network packets if needed for menu toggle:
```
type HUDTogglePacket = {
  IsOpen: boolean
}
```

## Files
**New files:** None.

**Modified files:**
- src/client/modules/HUDPrimitives.lua: Fixed duplicate applyStroke function (linter errors resolved).
- src/client/controllers/PlayerHUDController_new.lua: Reposition health bar above posture, add OpenUI/CloseUI toggle for ScreenGui.Enabled.
- src/client/controllers/CombatFeedbackUI.lua: Integrate posture bar into PlayerHUDController_new.lua core HUD (remove standalone).
- src/shared/network/NetworkTypes.lua: Add HUDToggle if not present.

**Delete:** src/client/controllers/PlayerHUDController.lua (superseded).

**Config updates:** None.

## Functions
**New functions:**
- PlayerHUDController_new.lua: `toggleCoreHUD(visible: boolean)` - sets screenGui.Enabled, integrates posture bar.

**Modified functions:**
- PlayerHUDController_new.lua: `createCoreHUD()` - use HUDPrimitives.StatBar for health/posture stacked vertically.
- CombatFeedbackUI.lua: `_BuildPostureBar()` - deprecated, move to PlayerHUDController_new.lua.
- InventoryController.lua: Fire HUDTogglePacket on toggle.

**Removed:** Old PlayerHUDController functions.

## Classes
No class changes. Controllers follow dependency injection pattern.

## Dependencies
No new packages. Uses Wally.toml packages (ProfileService, Signal). Roblox services (TweenService, RunService).

## Testing
- Run `ci/run_tests.lua` - all unit tests pass.
- Manual Studio test: Open inventory (`I`), verify HUD hides/shows, health above posture.
- Test posture updates from CombatService.
- Smoke test: Ring change notification.

## Implementation Order
1. [x] Fix HUDPrimitives.lua duplicate function (complete).
2. [ ] Integrate posture bar into PlayerHUDController_new.lua core HUD (health above posture).
3. [ ] Add OpenUI/CloseUI handlers in PlayerHUDController_new.lua (toggle screenGui.Enabled).
4. [ ] Update InventoryController.lua to fire HUD toggle remote.
5. [ ] Run tests, Studio verification.
6. [ ] Use GitHub CLI to triage issues, create blockers if missing, complete #183, close with comments.
7. [ ] attempt_completion
