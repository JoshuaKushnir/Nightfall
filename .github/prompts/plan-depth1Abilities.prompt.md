## Plan: Finish Depth-1 Abilities (Issue #172)

0. Preconditions and environment
Make sure you can run tests from the command line and from Studio.

Confirm --!strict is enabled at the top of:

src/shared/abilities/*.lua (Ash, Tide, Ember, Gale, Void).

All tests/unit/*Expression.test.lua files.

Ensure CI (if you have it) is configured to run the unit suite (and that this suite is the same one you run locally).

1. Deep audit of ability modules
Goal: every depth‑1 Expression ability has concrete, shippable behaviour, no stubs, and clear contracts.

Open each ability module:

src/shared/abilities/Ash.lua

src/shared/abilities/Tide.lua

src/shared/abilities/Ember.lua

src/shared/abilities/Gale.lua

src/shared/abilities/Void.lua

For each file, verify and/or refine:

Exports & structure

The module returns a clear table or function describing:

AbilityId / name

Branch / Aspect

MinDepth / cooldown / mana cost

OnActivate (and any other lifecycle methods: OnHit, OnEnd, etc.)

OnActivate contract

OnActivate(caster: Player | Character, context: AbilityContext) signature is consistent across abilities.

context should have a typed shape (e.g. ability id, target position, target entity, etc.) and be documented in a shared type module.

No dead code

Remove or replace:

Empty handlers (function() end stubs) that are never used.

Commented‑out legacy logic that will never ship.

Keep TODOs only if they are actionable and linked to an issue.

Error handling & guards

Null checks: if not character or not root then return end.

Range checks (for teleports/dashes).

Ensure you never assume Player.Character is non‑nil.

Movement system integration

For movement‑changing abilities (dash/teleport/knockback):

Use your existing movement helpers (if you have them) instead of re‑rolling translation logic.

Example: call a shared Movement.Dash(caster, direction, distance, duration) rather than setting HumanoidRootPart.CFrame directly.

Ensure that movement state (dash/dodge) respects current StateService rules (e.g. don’t fire dash if stunned).

Document each ability inline with minimal comments:

At top of each file, add:

A 1–2 line description of behaviour (“Ashen Step: short forward dash ~12 studs, if hitting an enemy apply minor posture damage”).

The player‑visible name and internal id.

Commit once this audit is done:

Commit message example:
feat(abilities): finalize depth-1 Expression behaviours for Ash/Tide/Ember/Gale/Void

2. Strengthen and standardize unit tests
Goal: tests describe intended behaviour, not just “no errors”. They become documentation and guardrails.

2.1. Shared testing utilities
If you don’t have one yet, add a small testing helper module, e.g. tests/TestUtils.lua:

Helpers:

createMockPlayerWithCharacter(position: Vector3).

advanceTime(seconds: number) if your framework supports time mocks.

assertVector3Within(actual, expected, epsilon) for movement checks.

assertAttribute(character, name, expectedValue) for status attributes.

Use this utility in all *Expression.test.lua files to avoid duplication.

2.2. AshExpression.test.lua
Existing plan: “assert caster moves ~12 studs after AshenStep.”

Implement and refine:

Arrange:

Create mock player + character at a known position (e.g. (0, 0, 0)).

Provide a forward direction / target position (if ability needs it).

Act:

Call Ash.OnActivate(caster, context).

Assert:

After appropriate simulated time (if needed), assert:

The new root position is ~12 studs forward (allow tolerance, e.g. ±1 stud).

The player state is still valid (not “Dead”, etc.).

Example assertion:

assertVector3Within(root.Position, expectedPosition, 1).

Edge cases:

If there is an obstacle directly in front, confirm the dash stops early / doesn’t clip through walls (if this is intended behaviour).

If the ability is on cooldown, OnActivate should fail gracefully (tested via AspectService/AbilitySystem, not necessarily in the Expression tests).

2.3. EmberExpression.test.lua
Plan: “after Ignite, character has HeatStacks > 0.”

Implement:

Arrange:

Mock player + character, ensure they have the HeatStacks field / attribute initialised to 0.

Act:

Call Ember.OnActivate(caster, context).

Assert:

After OnActivate, HeatStacks is > 0 (or exactly 1 if that’s the design).

If the ability applies a buff/debuff, assert relevant attributes ("Ignited" == true, or similar).

Negative paths:

If mana is insufficient or aspect depth too low (tested through service layer), ability should not change HeatStacks.

2.4. GaleExpression.test.lua
Plan: “after WindStrike, caster gets StatusWeightless attribute.”

Implement:

Arrange:

Mock player + character with no StatusWeightless attribute or set to false.

Act:

Call Gale.OnActivate(caster, context).

Assert:

character:GetAttribute("StatusWeightless") == true.

Optionally, if you have a duration, assert that removing / ticking down is handled by a timer or manager (via a separate test).

Ensure:

No errors if called twice in a row; either refreshes or ignores gracefully.

2.5. TideExpression.test.lua
Keep existing tests (“no errors and correct metadata”), but:

Add at least one behaviour assertion if there is any side effect:

Example: a small pull/push effect, or status effect.

2.6. Generic assertions
For all Expression tests:

Confirm:

No runtime errors in OnActivate.

Return value is as expected (if OnActivate returns success/failed reason).

All abilities respect --!strict (no type errors in tests).

Update tests until:

All tests/unit/*Expression.test.lua compile and pass under --!strict.

3. Ensure strictness and typing
For each ability module and test file:

Add --!strict at the very top if not present.

Resolve all type errors:

Add or refine type aliases in Shared/types/AspectTypes or a new AbilityTypes module if needed.

Annotate function signatures: OnActivate(caster: Player, context: AbilityContext).

For tests:

Ensure:

lua
local AbilityModule = require(path) :: AbilityModuleType
Use precise types for context objects.

Run static analysis (if using Roblox LSP / luau type checker) and fix any warnings that would realistically cause issues.

4. Run the full test suite locally
From your test runner (e.g. TestEz, custom framework):

Run all unit tests, not just the Expression tests.

Confirm:

0 failures.

No warnings related to missing mocks or nil references.

If any flakiness appears (e.g. tests depending on real time), stabilise by:

Injecting a fake clock or mocking async behaviour.

Avoiding reliance on actual RunService events in unit tests; keep those for integration tests.

If you have a pre‑commit hook or CI pipeline:

Ensure the updated suite runs and passes in that environment too (fix any path or require issues).

5. Update the session log (session-log.md)
Open session-log.md.

Add a new section with:

Date/time (ISO or your project’s standard).

Short title: "Implement depth-1 aspect abilities (Issue #172)".

Bullet list:

Ability modules audited: Ash, Tide, Ember, Gale, Void.

OnActivate implementations finalised (dash, teleport, stacks, status, etc.).

New assertions:

AshExpression.test.lua: AshenStep moves caster ~12 studs.

EmberExpression.test.lua: Ignite grants HeatStacks > 0.

GaleExpression.test.lua: WindStrike sets StatusWeightless.

All unit tests pass under --!strict.

Optional: Studio manual test results (Ash/Tide/Ember/Gale/Void Expression abilities verified via E key in Aspect system).

Include links / references to relevant files:

src/shared/abilities/*.lua

tests/unit/*Expression.test.lua

AspectService.lua (for casting path).

Save and commit.

6. Close issue #172 on GitHub
In the issue thread for #172:

Post a progress comment summarising:

All depth‑1 Expression abilities implemented with specific behaviours (1–2 bullets per aspect).

Unit tests added/updated:

Mention the three specific new assertions and that Tide tests remain and still pass.

State that the test suite passes locally under --!strict.

Mention manual Studio validation if you did it.

Example comment skeleton:

Status: Implemented and verified.

Finalised depth‑1 Expression abilities for Ash, Tide, Ember, Gale, Void.

New unit tests assert movement, stack gain, and status application for Ashen Step, Ignite, and Wind Strike.

All tests pass under --!strict and have been run locally and in Studio.

Closing #172.

Link the relevant commit or PR.

Close the issue in GitHub (or via the PR Fixes #172 if applicable).

7. Manual validation in Roblox Studio
(Optional but highly recommended to catch “feel” issues.)

Launch a local test place where:

Aspect selection is available (Ash, Tide, Ember, Gale, Void).

Keybinds are wired (e.g. E for the depth‑1 Expression ability).

For each aspect:

Equip that aspect (via your Aspect switching – you already have SwitchAspectRequest / AspectController G‑cycle).

Press E to trigger the Expression ability in‑game.

Validate:

Ash: dash distance feels correct (~12 studs, no clipping).

Ember: Ignite clearly shows stack behaviour (UI, damage, or other feedback).

Gale: weightless status visibly changes movement (jump / fall) or is clearly indicated.

Tide / Void: behaviours match design spec (pulls, teleports, status, etc.).

Record per‑aspect pass/fail in session-log.md (under this same entry).

Optionally capture short clips/gifs for later regression comparison.

8. Final polish / QA checks
Before calling this “perfect”, do a quick sweep:

Naming consistency:

Ability ids consistently follow one style (e.g. Ash_Expression_1 or AshenStep).

Test file names match ability names (AshExpression.test.lua -> Ash Expression ability id).

Logging:

Remove or demote noisy print/warn in production paths of abilities.

Keep one concise [Ability] or [AspectService] log per activation if needed for debugging, or guard them behind a debug flag.

Comments and TODOs:

Any remaining TODOs should be explicit and linked to new issues (e.g. -- TODO(#190): VFX polish for Ember Ignite.).

No ambiguous “fix later” comments.

Git hygiene:

Commit history for this work is clean:

One functional commit for code changes.

One for tests/log if you prefer separation.

CI (if present) green.

