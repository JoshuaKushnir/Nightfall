# NIGHTBOUND — PROGRESSION DESIGN ADDENDUM
### Design Exploration Document — February 2026
### Status: BRAINSTORM / PENDING SIGN-OFF — do not implement without a corresponding GitHub issue

This document captures two design discussions from a February 2026 session:
1. A proposed rework of the stat/build identity system to move away from Deepwoken-adjacent naming
2. A balance critique of the Omen system and proposed mechanical fixes

Neither section represents final spec. Both are here so the thinking isn't lost.

---

## SECTION 1 — STAT SYSTEM IDENTITY PROBLEM & PROPOSED REWORK

### The Problem

The current six stats — **Strength, Fortitude, Agility, Intelligence, Willpower, Charisma** — are Deepwoken's exact stat vocabulary. The mechanics behind them can be different, but the nouns are nearly identical. This is a design debt issue: Nightbound's identity should be legible on its own terms, and a new player's first look at a stat screen shouldn't immediately read as "this is Deepwoken."

The stat *effects* as currently implemented are fine. The naming and the investment model are what need rethinking.

---

### Proposed Solution: Rename Stats to Attunements

Replace the six stat names with **Attunements** — resonances with the forces that shape Vael. Players aren't building a stat sheet; they're describing what Vael has done to them over time. The names are rooted in the world's language rather than generic RPG vocabulary.

| Attunement | Replaces | What It Represents | Primary Effect Cluster |
|---|---|---|---|
| **Grit** | Strength | Raw endurance against the dark — scars that held | Health, break damage, melee scaling |
| **Veil** | Fortitude | Resistance to being read, touched, disrupted | Posture max, debuff resist, Omen growth slow |
| **Drift** | Agility | Fluency with the twilight's physics | Breath pool, dodge windows, movement speed |
| **Attune** | Intelligence | Depth of Aspect connection | Mana max, Aspect ability scaling, cast speed |
| **Temper** | Willpower | The internal cost of holding your shape | Mana half-rate drain, Omen growth reduction |
| **Presence** | Charisma | How the world perceives and responds to you | NPC disposition, faction standing speed, PvP intimidation passive |

The mechanical effects map 1:1 to the current implementation. This is a rename pass, not a systems rewrite. In code, `VALID_STAT_NAMES` in `ProgressionTypes.lua` is a string table — the change is a single constant swap once design signs off.

---

### Proposed Investment Model: Echoing (Supplemental to Point Allocation)

Deepwoken's model: click plus buttons, stat goes up. Clean, but generic. Nightbound already has **Resonance** as its core currency — the investment model should use that more meaningfully.

**Proposed model:** Attunements grow partially from *doing things that match the Attunement*, not only from clicking a button.

- **Grit** grows when you survive hits, get broken and recover, kill enemies through attrition
- **Veil** grows from blocking, resisting debuffs, dying at high Omen and coming back clean
- **Drift** grows from movement actions — dashes, vaults, mid-air redirects, extended sprints
- **Attune** grows from using Aspect abilities, spending Mana, exploring Aspect-responsive locations
- **Temper** grows from surviving in Ring 3+ without tipping over the next Omen threshold
- **Presence** grows from faction interactions, duels, helping revive players, NPC conversations

Each Attunement has **thresholds** (e.g. 0 → 20 → 50 → 100 → 200) rather than a per-point linear scale. At each threshold you unlock a **Resonance Trait** — a passive or enhancement specific to that Attunement's flavor. The scaling between thresholds is softer.

This means your build reflects how you actually play, not how you theory-crafted a stat screen before your first login. A player who spams Aspect abilities will naturally develop Attune. A player who brawls will develop Grit. You can cross-train, but it costs more time in Vael.

**Stat point allocation still exists** as a supplemental system — earned at Resonance milestones, used to fine-tune within Attunement tiers rather than being the primary engine. Think of them as adjustments, not the core identity driver.

---

### Build Identity Label: Discipline (Keep, Potentially Rename)

The computed Discipline label (Wayward / Ironclad / Silhouette / Resonant) derived from stat/Attunement dominance is already the right idea. It should stay. Consider whether the label names themselves need to feel more Nightbound-specific in a later pass — "Ironclad" and "Silhouette" are reasonably evocative, "Wayward" and "Resonant" are more generic.

This is a cosmetic rename consideration, lower priority than the stat name issue.

---

### Implementation Notes

- No code changes until this design is signed off and a GitHub issue exists
- The rename is a single constant change in `ProgressionTypes.lua` (`VALID_STAT_NAMES`) plus UI label strings in `ProgressionController.lua`
- The Echoing growth model (organic Attunement gain from behavior) is a new system requiring a new issue — it does not exist in the current implementation and would sit alongside the existing point allocation, not replace it

---

## SECTION 2 — OMEN BALANCE CRITIQUE & PROPOSED FIXES

### The Problem

As currently designed, Omen's costs are **social and logistical**, while its rewards are **combat-mechanical**. That's a broken risk/reward ratio.

The designed downsides of high Omen:
- NPCs refuse service / Wardens hunt you
- Your silhouette is corrupted (visible telegraph to other players)
- Other players are incentivized to hunt you for Shard rewards

These are costs that only matter *outside of combat*. A player who has committed to Ring 3+ as their operating zone doesn't care that a shopkeeper won't talk to them — they already have their gear. The telegraph (corrupted silhouette) is visible to skilled players, but Mark IV's 3-second invulnerability window is strong enough that the telegraph is a worthwhile trade. Being hunted is only a downside if you lose those fights, which a Mark IV/V player is well-positioned not to.

The design as written essentially says "the cost is that powerful players will come after you." That's not a cost — that's a target being placed on a player who probably enjoys the attention.

**Root cause:** Omen as designed is monotonically beneficial in combat, with costs only outside it. A well-designed risk/reward axis needs costs *inside* the domain where the rewards exist.

---

### Proposed Fixes

The following are proposed additions to the Omen system. All are brainstorm-level — none are specced for implementation.

---

#### Fix 1 — Luminance Vulnerability

High Omen players take increased damage from Luminance-adjacent attacks. Specifically:
- **Ember's heat signature** deals bonus damage to Omen-marked targets (the corruption is flammable)
- **Tide's cleansing pressure** disrupts Omen-derived abilities mid-use
- A **Radiant** weapon enchantment, available only to Warden-aligned players, deals bonus damage scaling with the target's Omen level

This creates genuine counterplay and a reason for build diversity. A clean player with the right Aspect + faction alignment *does* counter a high-Omen player — they have a specific tool. This rewards knowing your enemy and punishes treating Omen as a free upgrade.

---

#### Fix 2 — Scaled Shard Loss on Death

Currently everyone loses 15% of Resonance Shards on death (spec-gap placeholder, tracked in issue #129). High-Omen players should lose proportionally more:

| Omen Level | Shard Loss on Death |
|---|---|
| Mark 0 (clean) | 15% |
| Mark I–II | 20% |
| Mark III | 27% |
| Mark IV | 35% |
| Mark V (Convergent) | 45% |

The power you hold costs proportionally more when someone takes it from you. You can't camp permanently at Mark V without risking enormous loss every time someone catches you. This makes each death meaningfully hurt for high-Omen players in a way that scales with their investment.

Spec-gap: exact percentages need design sign-off. Table above is placeholder.

---

#### Fix 3 — Aspect Instability at High Omen

Currently Aspect overuse *causes* Omen. The reverse should also be true: high Omen makes Aspect abilities harder to control.

At Mark III and above, Aspect abilities have a small chance of:
- Costing bonus Mana (the corruption bleeds your channel)
- Triggering Omen residue regardless of which Aspect you're using (not just Marrow/Void)
- Misfiring — the ability fires but at reduced effectiveness or with a slight directional offset

You become volatile. Powerful but unstable. A character who can do enormous damage but requires more skill to play correctly, not less. This is the opposite of most games' power curves, which is exactly right for Nightbound's design philosophy.

Spec-gap: misfire chance percentages, residue gain amounts, and which abilities are affected need design sign-off.

---

#### Fix 4 — Ring 0 Hard Lock at High Omen

A Mark IV or V player should be **physically unable to enter Ring 0 (The Hearthspire)** without cleansing first. Not just NPC hostility — the Pillar Wardens actively block Drift Gate access at that Omen level.

This matters because Ring 0 is the social and economic hub: crafting, trading, restocking, faction services. If you're locked out, you're locked out of the entire player economy infrastructure. You can still play in Rings 1-5, but you're exiled from civilization.

This gives cleansing real mechanical pull rather than just cosmetic motivation. The question becomes: do you lean into what the darkness is making you, or do you pay the significant Shard cost to come back in from the cold? Both are valid. But the choice has real teeth.

Current design note: the Wardens "hunt you in Ring One" at Mark IV, but that's reactive (they come after you). The proposed change is proactive (you can't enter at all until you cleanse).

---

#### Fix 5 — Mark IV Invulnerability Rework

The current Mark IV ability (3-second shadow form invulnerability once per combat) has no in-combat cost. Proposed rework:

- Shadow form still works as designed: lethal hit triggers it, 3-second window
- **During shadow form, Omen drains accelerate** — you're burning corruption to stay alive
- **If you die while shadow form is expiring** (the window runs out while you're still in a lethal state), you lose an extra 0.5 Omen Marks toward the next threshold and take a significant Shard penalty on top of the normal death loss
- The ability can only trigger once per **respawn cycle**, not once per "combat" (combat is undefined and exploitable)

You bought time, but the dark took something for it. The ability is still strong — it kept you alive — but it isn't free, and it can make your situation actively worse if the fight goes wrong anyway.

---

### The Design Principle These Fixes Share

Every proposed fix adds a cost that lives *in the same domain as the reward*. Omen gives you combat power — the costs should also live in combat, not only in NPC dialogue and shopkeeper access. The social costs are fine and should stay. They're just not sufficient on their own.

The goal is a system where a clean player with the right build and knowledge genuinely has a fighting chance against a high-Omen player, even while acknowledging that the Omen player is stronger in the abstract. Counterplay should exist. Currently it doesn't.

The existing design doc line — *"the dark costs something, it's also worth something"* — is exactly right as a philosophy. These fixes are its mechanical expression.

---

## SPEC GAPS OPENED BY THIS DOCUMENT

These will need GitHub issues before any implementation begins.

| Gap | Section | Notes |
|---|---|---|
| Attunement name finalization (Grit / Veil / Drift / Attune / Temper / Presence or alternatives) | §1 | Needs design sign-off |
| Echoing growth model — per-action Attunement gain values and thresholds | §1 | New system, new issue required |
| Resonance Trait table — what each Attunement threshold unlocks | §1 | Entirely unspecced |
| Discipline label rename consideration | §1 | Low priority cosmetic pass |
| Omen Shard loss scaling per Mark (exact percentages) | §2 Fix 2 | Placeholder table above |
| Aspect instability misfire chance and residue values per Mark | §2 Fix 3 | Entirely unspecced |
| Ring 0 Drift Gate lock threshold (Mark IV? Mark III+?) | §2 Fix 4 | Needs design sign-off |
| Mark IV shadow form Omen drain rate and expiry-death penalty | §2 Fix 5 | Needs design sign-off |
| Luminance vulnerability bonus damage percentages | §2 Fix 1 | Needs balance pass |
| Radiant enchantment unlock conditions and damage scaling | §2 Fix 1 | Needs design sign-off |

---

## WHAT TO DO WITH THIS DOCUMENT

1. Read it when returning to Progression or Omen implementation work
2. For each section you want to act on: create a GitHub issue first, then reference the section here in that issue's body
3. Do not treat anything in this document as final spec — it is all pending sign-off
4. When a section is formally specced and issued, annotate it here with the issue number so this doc stays useful as a map

---

*Document authored: February 2026 — Session following NF-042*
*Covers: stat naming brainstorm, Attunement model proposal, Omen balance critique, five Omen fix proposals*