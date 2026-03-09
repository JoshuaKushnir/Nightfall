# Dev: Spawnable Test Dummies

Purpose
- Quick, in-game way for devs/QA to verify attacks, hit registration, and client feedback.

How to spawn
- Client debug hotkey: `J` (requires `DebugInput` enabled)
- Admin command (local-only prompt or hotkey): `/admin spawn_dummy [here|x y z]` or press `Ctrl+Shift+J` to spawn a dummy in front of you. (Command input is not sent to public chat.)
- Programmatic (client): Fire `ReplicatedStorage.NetworkEvents.SpawnDummy` with a `Vector3` position
- Programmatic (server): `DummyService.SpawnDummy(position)` → returns `dummyId`

Server API
- `DummyService.SpawnDummy(position)` -> string? (dummy id)
- `DummyService.DespawnDummy(dummyId)` -> nil
- `DummyService.ApplyDamage(dummyId, amount)` -> boolean (true if still alive)

Notes
- Remote spawn/despawn is restricted to development (Studio) to prevent abuse in production.
- Dummies are visual models named `Dummy_<id>` and include a `Humanoid` for compatibility with existing systems.
  An `Animator` object is now also parented to the Humanoid so clients can
  load animations with `AnimationLoader`.  (Previously the missing animator
  produced repeated "No Animator found" warnings.)
- CombatService treats dummies like targets for damage and will emit `HitConfirmed` events so `CombatFeedbackUI` shows damage numbers.

Tests
- Unit tests added: `tests/unit/DummyService.test.lua` — validates spawn/despawn and damage behavior.

File locations
- Server: `src/server/services/DummyService.lua`
- Client visuals: `src/client/controllers/DummyController.lua` (idle
  animation uses the shared database entry instead of requiring an
  animation folder)

  **Preloading:** MovementController now calls
  `AnimationLoader.PreloadAll` during startup so all DB animations are
  cached on the player's humanoid.  This eliminates the "first swing
  takes a few tries" problem—the client already has the clip loaded
  when gameplay begins.
- Shared types: `src/shared/types/DummyData.lua`
- Debug input: `src/client/modules/DebugInput.lua`

Usage examples
- Client keypress: Press `J` while running in Studio to spawn a dummy 10 studs in front of the player.
- Server script: `local id = DummyService.SpawnDummy(Vector3.new(0,5,0))`

---
Docs added as part of Issue #64 (spawnable test dummies).