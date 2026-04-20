# TODO.md - Nightfall MVP Implementation Steps

From approved implementation_plan.md. Progress tracked with [x].

task_progress Items:
- [x] Step 1: Fix HUDPrimitives.lua duplicate function (complete).
- [x] Step 2: Integrate posture bar into PlayerHUDController_new.lua core HUD (health above posture). [DONE — PlayerHUDController.lua has posture bar fully built, stacked below health via UIListLayout, confirmed in session review]
- [x] Step 3: Add OpenUI/CloseUI handlers in PlayerHUDController_new.lua (toggle screenGui.Enabled). [DONE — HideHUD()/ShowHUD() methods exist and set clusterGui.Enabled]
- [x] Step 4: Update InventoryController.lua to fire HUD toggle remote. [DONE — InventoryController.ToggleOpen() calls self._hud:HideHUD()/ShowHUD()]
- [ ] Step 5: Run tests, Studio verification.
- [ ] Step 6: Use GitHub CLI to triage issues, create blockers if missing, complete #183, close with comments.
- [ ] Step 7: attempt_completion
