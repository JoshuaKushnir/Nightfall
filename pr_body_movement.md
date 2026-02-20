Draft PR — movement refactor & playtest fixes (refs #95)

Summary:
- Modular movement state machine (Idle/Walk/Sprint/Jump/Slide/WallRun/Vault/LedgeCatch/Climb).
- Fixes: vault clipping/landing, manual vault start, climb ? hang ? manual pull-up (0.4s grace), wall-run "stickiness" & breath drain, slide/sprint scaffolds, animation wiring via AnimationLoader.

Key files changed:
- src/client/controllers/MovementController.lua
- src/shared/movement/states/{Climb,LedgeCatch,WallRun,Vault,Slide,Walk,Jump,Idle,Sprint}.lua
- src/shared/modules/MovementBlackboard.lua
- src/shared/movement/StateContext.lua
- docs/session-log.md

Playtest notes (Studio):
- Vaults no longer clip and land correctly on thin/deep obstacles.
- Wall-running sticks to the wall and drains Breath until you jump or exhaust.
- Climb now transitions to a hang; pull-up requires a second Space press (0.4s grace to avoid accidental auto-pull).
- Ledge hang position/offsets tuned to prevent corner clipping.

Follow-up checklist (tracked separately as issues):
- [ ] Add mantle/pull-up animation + server-side validation for climb/ledge (Phase 2)
- [ ] Add unit/integration tests for new state modules (Vault/LedgeCatch/Climb/WallRun/Slide)
- [ ] QA thin ledges, holding Space during ledge entry, wall-run chaining at momentum cap

Linked issue: #95

Notes: This is a DRAFT PR for review & QA. Ready for splitting into smaller PRs if requested.
