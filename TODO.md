# TODO.md — Nightfall MVP

Issue: #183 — HUD Revamp (in progress)

## Completed
- [x] Fix HUDPrimitives nil-value crash (applyStroke/applyCorner export)
- [x] Remove broken PlayerHUDController_new.lua (merged into PlayerHUDController)
- [x] Create HUDTheme.lua (shared cluster geometry + colour tokens)
- [x] Add ManaBlue to UITheme.Palette
- [x] Implement Deepwoken-style bottom-centre HUD cluster
    - HP bar (340 px, gold fill, damage flash, crit pulse, aspect border)
    - Posture bar (grey → amber → red)
    - Mana bar (70 % width, ManaBlue)
    - Breath bar (55 % width, teal → red + exhausted overlay)
    - Status icon row (8 effects, attribute-driven)
    - Ability slot row (4 slots with cooldown overlay)
    - Resonance pip row (5 dots)
    - Dark gradient scrim backdrop
    - Persistent RING N label (top-right)
    - Zone/ring notification (gold dividers, 3.5 s hold)
- [x] Migrate posture bar ownership from CombatFeedbackUI → PlayerHUDController
- [x] Remove standalone posture ScreenGui from CombatFeedbackUI

## Remaining (#183)
- [ ] Wire ability slots to AbilitySystem cooldown events
      PlayerHUDController.SetSlotCooldown(index, duration) is ready;
      AbilitySystem needs to call it on the client after each cast.
- [ ] Add OpenUI/CloseUI toggle: PlayerHUDController:HideHUD() / :ShowHUD()
      InventoryController should call HideHUD on open, ShowHUD on close.
- [ ] Studio playtest verification (bars update, flash, zone notification)
- [ ] Close issue #183 after verification