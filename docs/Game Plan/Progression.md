# NIGHTBOUND — PROGRESSION & THE THREE PILLARS
### Design Expansion Document

<!--
COPILOT CONTEXT
================
This is the deep-design expansion for the progression systems summarised in Main.md.
Impl files: DataService.lua, PlayerData.lua, AbilitySystem.lua, AbilityRegistry.lua,
            WeaponService.lua, WeaponRegistry.lua, WeaponTypes.lua, StateService.lua

SPEC GAPS IN THIS FILE:
  - Resonance Shard loss-on-death formula: no numbers
  - Groove depth thresholds (Whisper/Resonant/Soulbind): no use-count or time targets
  - Discipline stat differences: all qualitative, no numeric tables
  - Cross-training Resonance cost: percentage anchor exists, no baseline Shard total
  - Aspect branch unlock costs: no Resonance cost table
  - Omen accumulation rates per trigger: no values
  - Omen cleansing cost curve: "escalating" with no numbers
  - Aspect cross-synergy bonuses: named and described, no numeric values
-->

---

## PROGRESSION PHILOSOPHY

Nightbound's progression is built on a simple covenant with the player: time spent in the world is never wasted, and moving forward is always the right choice. Death slows you. Safety stagnates you. The dark ahead holds everything you need.

The three systems that power progression — Resonance, Weapons, and the Pillar framework — are not independent ladders. They're interlocking pressures. Each one creates demand that the others satisfy, and each one becomes more meaningful the further into Vael a player ventures.

---

## RESONANCE — THE CORE GROWTH SYSTEM

### What Resonance Is

Resonance is not a level. It is an attunement — a measure of how deeply your character has absorbed the ambient power of Vael. It accrues through everything: killing enemies, surviving prolonged fights, exploring new territory, successful crafting, completing NPC requests, and simply enduring in zones that want you dead. It is deliberately multi-sourced so that no playstyle is cut off from progress.

Resonance does two jobs. First, it functions as a soft gate — unlocking higher tiers of ability upgrades, weapon mastery thresholds, and Ring access. Second, it functions as a risk currency — Resonance Shards drop on death, slowing your forward progress without reversing it. The core tension: accumulate Resonance faster by pushing into dangerous zones, but risk losing more of it when things go wrong.

### Resonance vs. Resonance Shards

These are two distinct layers and the distinction matters.

**Resonance** (the raw stat) is permanent. You cannot lose the total Resonance you've accumulated. Every upgrade you've unlocked, every threshold you've crossed — that stays.

**Resonance Shards** are the in-flight currency — the progress toward your next threshold. Losing Shards on death costs you momentum, not history. A player who dies repeatedly still retains every upgrade they've already unlocked.

> *Design intent: The system should feel like falling behind, not being set back. Other players pulling ahead while you respawn is more motivating than losing what you've built.*

### Soft Cap Structure Per Ring

Each Ring imposes a soft cap on Resonance growth. You can reach a ceiling in Ring One — fully specced within that cap — but further growth requires entering Ring Two. This is intentional. Grinding in safety forever is not a viable path to power. The world rewards those who venture forward.

| Ring | Name | Resonance Soft Cap | Unlocks at Cap | Diminishing Returns Onset |
|------|------|--------------------|----------------|--------------------------|
| 0 | The Hearthspire | None (social only) | Starting equipment access | Immediate |
| 1 | The Verdant Shelf | Tier 1 | Core Aspect branches (tier 1), Discipline spec, basic weapons | 75% of cap |
| 2 | The Ashfeld | Tier 2 | Omen activation, Aspect cross-synergies, advanced crafting | 80% of cap |
| 3 | The Vael Depths | Tier 3 | Weapon Groove unlocks, Memory Fragment access, Aspect tier 3 | 82% of cap |
| 4 | The Gloam | Tier 4 | Dark Adaptation, Omen path 4–5, legendary crafting | 85% of cap |
| 5 | The Null | No cap | Full power, Convergence participation | N/A |

### The Shard Economy in Practice

Resonance Shards accumulate at a rate influenced by three factors: the danger level of the zone you're in, your Living Resonance streak multiplier, and whether you're engaging meaningfully with the world versus passively existing in it. Farming the same low-tier enemies in Ring One will eventually yield negligible Shards — the world notices stagnation.

The ideal Resonance session involves a player consistently pushing slightly past their comfort zone. Deeper zones yield more Shards per engagement, more Shard drops on death (raising stakes), and unlock richer Codex entries and crafting materials that create downstream advantages.

### Resonance Grooves — Weapon Depth

> **Status:** 📐 DESIGNED
> **Impl files (target):** `WeaponService.lua` (track use count), `WeaponTypes.lua` (groove depth field), `WeaponRegistry.lua`
> **❓ SPEC GAP — depth thresholds need numbers:**
>
> | Threshold | Name | Use-count target | Notes |
> |-----------|------|-----------------|-------|
> | 1 | Whisper Slot | ??? | TBD |
> | 2 | Resonant Slot | ??? | TBD |
> | 3 | Soulbind | ??? | TBD; becomes account-persistent in Ashen Record |

Every weapon has a hidden Resonance Groove that deepens through use. This is weapon-specific — the Groove on a blade you've used for forty hours is meaningfully different from a fresher blade of the same type. At three depth thresholds, the Groove opens a slot for an Aspect-infused modification unique to that weapon type.

**Depth 1 — Whisper Slot.** Minor passive. A sword might gain a slight parry timing extension, a spear a reduced stamina cost on thrusts. Cosmetic tells appear on the weapon.

**Depth 2 — Resonant Slot.** Active modification. A ranged Aspect pulse on heavy strikes, a brief counter-aura on successful blocks, terrain-reactive effects. Tide-infused weapons used near dried riverbeds might briefly restore water. Ember-infused blades leave burning contact traces on terrain.

**Depth 3 — Soulbind.** The weapon becomes account-persistent. It survives character resets and appears in your Ashen Record. Its visual identity shifts permanently — the weapon remembers its history in visible ways. You can never fully lose it. Choosing which weapon to Soulbind is one of the most significant decisions a player makes.

> *Grooves reward commitment. Swapping weapons constantly delays depth. Building around a single weapon's Groove is a meaningful build strategy, not an afterthought.*

---

## MOVEMENT IN PHASE 2 — THE ASHFELD

> **Status:** 📐 DESIGNED
> **Impl files (target):** `MovementController.lua` (terrain modifiers, Breath cost scaling), `MovementConfig.lua` (zone constants), `StateService.lua` (surface-type detection)
> **❓ SPEC GAPS:**
>   - Exact Breath multipliers per surface type (crumbling stone, dried riverbed, dead canopy)
>   - Momentum cap adjustment for Phase 2 zones vs Ring One baseline
>   - Whether surface-type detection is server-authoritative or client-predicted

The Ashfeld is where movement stops being a neutral skill and becomes a strategic variable. Ring One's terrain — the Verdant Shelf — is largely forgiving: stable ground, predictable elevation, readable sightlines. Ring Two is none of those things. Dead forests with root systems that rise through broken stone. Dried riverbeds running between crumbled embankments. Pre-twilight infrastructure at irregular collapse — floors that hold, floors that don't, walls at angles not designed for traversal. The Ashfeld is not hostile to movement. It is indifferent to it, and that indifference kills players who haven't adjusted.

### Terrain Surface Modifiers

The Ashfeld introduces distinct surface types that modify movement behaviour. This is not a blanket zone debuff — it is terrain-specific. Players who learn the Ashfeld learn to read the ground.

| Surface | Effect on Movement | Aspect Interaction |
|---------|-------------------|-------------------|
| Crumbling stone | Dash momentum does not fully carry — 15–25% reduction on exit angle (TBD) | Void phase-dash passes through unstable sections entirely |
| Dried riverbed | Reduced traction on sprint changes; slide distance cut | Tide Communion temporarily restores traction and extends slide range |
| Dead root canopy | Obstructs aerial paths; Gale redirect is blocked if path intersects canopy mesh | Gale Communion identifies canopy gaps from below — visible as subtle wind pressure tells |
| Ashfield ruins (stable floor) | No modifier; functions as Ring One baseline | — |
| Ashfield ruins (unstable floor) | Weight-triggered collapse on sustained sprint; walking or crouching is safe | Ironclad Discipline characters trigger collapse faster — known tradeoff |

> *Design intent: the terrain modifiers should feel discovered, not explained. Players learn the Ashfeld's movement grammar by running through it and feeling resistance. No tooltip. The world teaches through consequence.*

### Breath Cost Scaling in Phase 2

> **❓ SPEC GAP — values needed before impl**
>
> | Action | Ring 1 Breath Cost | Ring 2 Multiplier | Notes |
> |--------|--------------------|-------------------|-------|
> | Sprint | (baseline) | ×1.15 — 1.25? | Ashfeld ambient pressure |
> | Dash | (baseline) | ×1.0 — no change? | Ash/Void exception |
> | Wall-run | (baseline) | ×1.3? | Crumbling grip degrades faster |
> | Dash chain (2nd+) | (baseline) | ×1.2 — 1.35? | Chaining punished more in Phase 2 |

Sustained movement in the Ashfeld costs more Breath than Ring One. Not dramatically — this is not a stamina wall — but enough to be felt by players who chain dashes and sprint constantly. The intended effect is to reward measured movement over reckless pace. A Silhouette build in the Ashfeld who times their Breath recovery correctly is still faster than an Ironclad sprinting with no concern for cost. But a Silhouette who chain-dashes into a fight with no Breath reserve is punished harder than they would be in Ring One.

Discipline differences are pronounced here. Silhouette's Ghoststep advantage partially offsets the Breath multiplier — the reduced recovery frames mean each Breath-per-dash is spent more efficiently even if the nominal cost is higher. Ironclad players feel the Breath multiplier most acutely but have less need for constant movement in the first place; their gameplay cadence in the Ashfeld is closer to positioning than traversal.

### Resonance Echoing and Movement Signatures

Phase 2 introduces Resonance Echoing — Aspect abilities leave environmental traces that persist briefly. This applies to movement too. Aspect-enhanced movement leaves a signature in the Ashfeld terrain that didn't appear in Ring One.

- **Ash dash trails** in the Ashfeld linger longer than Ring One's near-instant fade. The dry air preserves them. An Ash player moving quickly through a corridor leaves a trail that persists for several seconds — useful for false pathing (deep Ash Communion), dangerous as a readable tell for a pursuing player.
- **Tide slides** across dried riverbeds leave visible moisture traces for a short window. Tide players can read their own trails to understand where water restoration occurred, which opens specific traversal paths that are not available immediately after.
- **Ember sprint acceleration** leaves brief thermal traces on the ground. Visible only to Ember players (and Marrow Communion at depth), but a meaningful give if fighting an opponent with that read.
- **Gale aerial redirects** produce visible wind pressure in the Ashfeld's dust — a puff of disturbed particulate at the redirect point. In a chase, it tells a pursuer exactly where the redirect fired.
- **Void phases** leave a brief spatial distortion at the entry and exit point. Not the player's position — the phase corridor itself. A skilled opponent can read entry/exit to predict position.

Movement in Phase 2 is therefore a form of writing. Everything you do leaves a record. Learning to move without broadcasting your next position is a skill the Ashfeld specifically teaches.

### Aspect-Specific Movement Advantages

The Phase 2 terrain is unequal across Aspects in ways that matter. These are not tuned for balance — they're tuned for identity. Some Aspects genuinely move through the Ashfeld better than others, and that asymmetry is by design.

**Tide** is the most transformed Aspect in Phase 2. Dried riverbeds are the Ashfeld's dominant terrain feature, and Tide Communion players can restore traction and briefly expand water paths, creating traversal routes that do not exist for other Aspects. This is not a minor advantage — there are deliberate routing puzzles in the Ashfeld that Tide players resolve through movement that everyone else has to go around.

**Gale** discovers that the Ashfeld has significant vertical space that Ring One didn't meaningfully exploit. Collapsed structures create elevation differentials. The canopy gaps are navigable for Gale players with Communion depth — they literally move through a different version of the zone. Ground-level players may not see them until they drop in.

**Void** handles unstable terrain without the collapse trigger — phasing through a surface-type that would slow or collapse for other Disciplines means Phase 2's most hazardous terrain becomes a strategic resource. Void players route through areas other Disciplines avoid.

**Ash** benefits most from the Ashfeld's long trace persistence. Ring One's short trail decay meant Ash false-pathing required precise timing. In Phase 2, trails linger, and an Ash player who understands this can create convincing false movement histories without slowing down. The Ashfeld is Ash's home terrain in PvP contexts.

**Ember** finds the Ashfeld's relatively open ground between ruined structures suited to its sprint acceleration signature. The Ashfeld lacks Ring One's dense canopy blocking sprint lines. Ember in Phase 2 is faster than anywhere in Ring One — with the caveat that sprint traces are highly visible here.

**Marrow** has the most unusual Phase 2 movement property: Marrow Communion at depth perceives degrading terrain as a Poise resource. Unstable floors that would slow other players are registered as dying ground — a stat Marrow can briefly extract from. The implementation of this is a Poise regeneration tick on contact with collapse-state terrain. (Spec gap: exact Poise gain per contact, duration before collapse, whether this requires active Communion ability or is passive at depth 2+.)

### Phase 2 Movement — Design Summary

The Ashfeld is the first zone where movement literacy becomes a loadout variable, not just a skill. Players arrive with movement habits from Ring One and spend time in Phase 2 having those habits checked. The correct response is not to abandon what works — it's to add terrain reading to the skill set. The players who move best in the Ashfeld are the ones who stopped trying to move through it and started moving with it.

This is the progression delivered by environment, not by a stat screen.

---

## THE THREE PILLARS

Every Drifter in Nightbound is defined by the intersection of three systems: **Aspect** (elemental-spiritual identity), **Discipline** (physical mastery), and **Omen** (the dark variable). These three pillars are intentionally distinct enough to allow radically different playstyles but intertwined enough that ignoring any one of them creates a meaningful tradeoff rather than an obvious mistake.

---

## PILLAR ONE — ASPECT

Aspect is your elemental-spiritual identity. It determines how you interact with Vael's ambient power, what abilities you develop, and how the world responds to your presence. Aspect is chosen at character creation but expressed over dozens of hours of investment. It is the most visible part of a build — the thing other players read first.

### The Six Aspects

| Aspect | Identity & Theme | Signature Strength | Movement Modifier |
|--------|-----------------|-------------------|------------------|
| Ash | Concealment, misdirection, lingering trace | Deception — enemies and players may target false afterimages | Dash leaves decoy trails |
| Tide | Flow, pressure, restoration | Terrain control — Tide abilities reshape the battlefield and restore dried areas | Slides further; momentum preserved on wet surfaces |
| Ember | Aggression, acceleration, heat | Sustained offense — Ember builds stacks that amplify damage the longer a fight lasts | Faster sprint acceleration |
| Gale | Speed, altitude, redirection | Aerial pressure — Gale excels at controlling space and punishing stationary targets | One mid-air directional redirect per jump |
| Void | Phase, distance, silence | Disruption — Void abilities interrupt Posture recovery and phase through defenses | Brief phase through geometry corners on cooldown |
| Marrow* | Corruption, endurance, hunger | Attrition — Marrow abilities drain resources and build Omen passively in the user | Regenerates Poise faster during movement |

*\* Marrow available from Second Dimming onward.*

### The Three Branches

Each Aspect divides into three investment branches. Players spend freely across all three but are incentivized by diminishing cross-branch returns to commit somewhere. Specialization is rewarded without being required.

#### Expression — Offensive Abilities

Expression defines how your Aspect damages, disrupts, and controls. Deep Expression builds hit harder and have more dramatic visual signatures. Expression abilities are aimed, timed, or chargeable — there is no auto-aim. A missed Ember burst in a fight is a genuine mistake with real consequences.

Expression abilities generally affect Posture more than HP, which means they're used to create Break windows rather than deal direct damage — with exceptions in deep builds. The deeper the Expression investment, the more Aspect abilities can shift from Posture tools into direct threat options.

Expression synergizes directly with the Resonant Discipline. Resonant characters convert Aspect Expression power into weapon hits, creating hybrid melee-caster builds that feel distinct from both pure fighters and pure casters.

#### Form — Passive Combat Modifications

Form modifies how your character inhabits the fight rather than what they do during it. Passive Posture bonuses. Improved recovery between Aspect uses. Resistance to specific damage types. Movement bonuses during specific stances.

Form is the invisible architecture of a build — the layer that turns a good setup into an efficient one. It doesn't announce itself with flashy ability activations. It shows up as a pattern over hundreds of engagements: you survive things you shouldn't, recover faster than opponents expect, move in ways that seem just slightly off from what they anticipated.

A deep Form investment in Void produces a character who seems to recover from stagger impossibly quickly. A deep Form investment in Tide creates someone whose Posture is difficult to break because they're constantly absorbing kinetic energy from the environment. These differences are felt across dozens of fights before a player consciously identifies them.

#### Communion — Utility and Exploration

Communion governs how your Aspect interacts with the world beyond combat. It produces the most distinctive playstyle differences between Aspects and is where exploration builds live. A deep Communion investment changes what the game looks like — literally, in some cases.

- **Ash Communion** — False-path generation. An Ash player can leave persistent decoy trails in the environment — useful for confusing pursuing players, misleading enemies, or (rarely) deceiving NPCs. In the open world, deep Ash Communion makes leaving and re-entering an area a tactical decision rather than just travel.

- **Tide Communion** — Environmental water detection and restoration. Deep Tide Communion can sense underground water sources, briefly restore dried riverbeds, and unlock passages sealed by drought. In the Ashfeld specifically, Tide Communion players can find routes through the dead landscape that don't exist for anyone else.

- **Ember Communion** — Heat reading. Ember players with deep Communion detect warm-blooded enemies through walls at close range, see heat signatures left by recent movement, and can ignite specific environmental elements to create light sources or hazards. The scout class of the Aspect system.

- **Gale Communion** — Extended aerial traversal. Wall-run duration increases. Wind currents in the environment become visible and rideable. Gale players find vertical shortcuts others miss entirely. Learning a region as a Gale Communion build means learning a different version of that region.

- **Void Communion** — Phase sensing. Detect invisible enemies. Sense traps before triggering them. Interact with specific objects that require phase-touching. In PvP, Void Communion players can see slightly further through low-visibility conditions. In Ring Four, this is the difference between ambush and anticipation.

- **Marrow Communion** — Biomass reading. Detect creature health thresholds. Sense dying enemies or diseased plants. In the Ashfeld and the Vael Depths, Marrow Communion players perceive environmental detail others cannot — corrupted soil, diseased root systems, residual death saturating specific locations. Some Codex entries only fill in through Marrow Communion interaction with the environment.

### Cross-Aspect Synergies

Certain Aspect combinations produce passive bonuses that don't exist in either Aspect alone. These are not mandatory — a focused single-Aspect build is fully viable — but they reward experimentation and create builds that feel genuinely unique.

| Combination | Synergy Name | Passive Effect |
|-------------|-------------|----------------|
| Ash + Void | Deepghost | Dash trails also briefly reduce the player's Luminance signature — harder to track in dark zones and PvP |
| Tide + Gale | Stormfront | Sustained Aspect usage produces minor wind gusts and water vapor, partially obscuring vision in a small area |
| Ember + Marrow | Cauterize | Marrow's self-damage component converts to Posture recovery; Ember's heat stacks slow the Marrow drain rate |
| Ash + Tide | Mistveil | False trails persist longer and are harder for enemies to distinguish from actual player movement |
| Gale + Void | Slipstream | Phase-through geometry on dash; Gale's mid-air redirect can chain once with the phase |
| Ember + Gale | Ignition Draft | Airborne targets take bonus Ember damage; Ember terrain trails linger longer when Gale wind passes through |

### Aspect as World Identity

Aspect isn't just a combat system. It shapes how NPCs respond to you, which environmental details you can perceive, and how other players read you in the open world. A Void player moving through The Hearthspire leaves subtle tells — a slight shimmer, a momentary dulling of nearby light sources — that experienced players learn to recognize. An Ember player entering a tense NPC conversation might find the room's temperature rising, certain faction representatives slightly wary.

This is deliberate. Aspect should feel like a costume you live in, not a menu you select from.

---

## PILLAR TWO — DISCIPLINE

> **Status:** 📐 DESIGNED
> **Impl files (target):** `PlayerData.lua` (disciplineId field), new discipline-check functions in `WeaponService.lua`
> **❓ SPEC GAP — no numeric stat tables. Each Discipline needs:**
>   - Base Breath pool
>   - Breath drain multiplier (sprint/dash/wall-run)
>   - Base Poise and Poise recovery rate
>   - Weapon weight class access list
>   - Aspect scaling coefficient per branch

Discipline governs how your body works — physical capability, weapon proficiency, and the relationship between your physical output and your Aspect usage. It is chosen at character creation but can be cross-trained, at significant Resonance cost, to add secondary competencies.

### Wayward — Balanced Adaptability

Wayward exists to serve players who don't yet know what they want, or who deliberately choose flexibility as their identity. Wayward characters have no strong stat peaks but no critical weaknesses. They can use every weapon weight class at reduced proficiency. Their Aspect scaling is moderate across all branches.

The trap of Wayward is that it never forces a build decision. The strength of Wayward — when intentionally committed to — is that it can pivot mid-fight, mid-session, and mid-zone without a respec. A veteran Wayward player who has deliberately unlocked cross-training branches is one of the most adaptable characters in the game. The ceiling is lower but the floor never disappears.

> *Wayward is the entry point. It is not the easy choice — undirected flexibility is weaker than focused commitment. Playing Wayward well requires knowing what every other Discipline does and consciously choosing not to be any of them.*

### Ironclad — Weight and Permanence

Ironclad is the weight class. Heavy weapons. Armor proficiency. Poise scaling that makes you a wall when other Drifters are stumbling. Ironclad characters accumulate Poise from taking hits — a system called **Tempered Stance** — that means the longer an Ironclad stays in a fight, the harder they become to stagger.

Ironclad has the worst Breath efficiency of any Discipline — movement costs more and recovers slower. This is intentional. Ironclad is a statement: *I will not be moved. I will outlast you.* The trade-off is that an Ironclad caught without terrain support is dangerously exposed to mobile opponents.

Ironclad scales poorly with Resonant builds but exceptionally with Void (phase-movement patches mobility gaps) and Marrow (attrition plus Poise endurance creates an almost unkillable slow-pressure build).

### Silhouette — Speed and Efficiency

Silhouette is the mobility class. Light weapons. Reduced Poise baseline but dramatically improved Breath efficiency — Silhouette characters sustain movement chains longer than any other Discipline. Their signature passive, **Ghoststep**, reduces dash recovery frames slightly, enabling chain-dashes that feel almost supernatural at high skill.

Silhouette specializes in creating and exploiting Clash moments. They're fast enough to trigger intentional Clashes and practiced enough to execute the follow-up window reliably. Their offensive ceiling is lower than Ironclad in a sustained exchange, but they rarely allow sustained exchanges. A Silhouette build is about precision and denial: you don't absorb damage, you refuse to be where damage lands.

Silhouette scales exceptionally with Ash (trails buy time to disengage and reposition), Gale (aerial mobility chains become devastating), and Ember (acceleration into melee range with heat stacks already building).

### Resonant — The Weapon as Instrument

Resonant is the hybrid class. It trades physical stat investment for Aspect amplification — a Resonant character hits like a Silhouette with weapons but their Aspect abilities hit like a fully-specced Expression build. The tradeoff is deliberate management: you're feeding two systems simultaneously and the timing windows for optimal play are tighter.

Resonant is the only Discipline that unlocks **esoteric weapons**: instruments (which produce area Aspect fields), focuses (off-hand items that amplify a single Aspect branch), and staffs (which convert all melee damage to Aspect-typed). These are not available to other Disciplines regardless of Resonance investment.

Resonant players read as unusual in the open world. Their weapons often glow or hum. Their strikes produce visible Aspect telltales on contact. They are identifiable — which means they are targeted. The payoff for surviving that targeting is a character with no parallel in the game's design.

### Cross-Training

> **❓ SPEC GAP:** Cross-training cost is described as ~40% of full spec cost, but no baseline Resonance Shard total exists for any Discipline. Define baseline before implementing.

Cross-training into a secondary Discipline requires a Resonance investment equivalent to approximately 40% of the cost to fully spec the target Discipline. You gain access to the bottom tier of that Discipline's passives and weapon proficiency — not the signature abilities, but the foundation.

The most common cross-trains and their strategic rationale:

- **Ironclad secondary on Silhouette** — Patches the Poise vulnerability. Silhouette-primary players who eat too many hits occasionally find themselves unable to execute their movement. A light Ironclad investment creates a buffer without sacrificing the Ghoststep advantage.

- **Silhouette secondary on Resonant** — Breath efficiency for hybrid players. Managing Aspect usage and movement simultaneously is Breath-hungry. Silhouette cross-training reduces movement costs, buying more room for Aspect activity.

- **Resonant secondary on any physical Discipline** — Unlocks Aspect-enhanced combat options without committing to a full Resonant identity. The most common is Ironclad-primary with Resonant secondary — the Poise endurance of Ironclad with Aspect amplification to create devastating Break setups.

---

## PILLAR THREE — OMEN

> **Status:** 🚫 FUTURE — Do not implement until after Ring One combat is stable.
> **Impl files (target):** `PlayerData.lua` (omenMarks: 0–5), `StateSyncService.lua` (visual state broadcast), new `OmenService.lua`
> **❓ SPEC GAPS:**
>   - Per-trigger accumulation values (e.g. Ring One death = +0.1 Mark? Ring Four = +0.5?)
>   - Cleanse cost curve (Resonance Shards per Mark, per attempt)
>   - Passive Luminance drain rate at Mark V (units/sec?)
>   - "Full in-game week" for Convergent Ashen Record entry — define in real time

Omen is the dark variable. It is not chosen — it accumulates. Every Drifter begins with zero Omen. It builds through dying, spending extended time in deep zones, specific Ashen Choir interactions, overuse of certain Aspect abilities, and — crucially — from choices the player makes. Omen is the game's moral texture made mechanical.

### The Five Thresholds

Omen accumulates in Umbral Marks across five distinct thresholds. Each threshold carries a passive corruption ability, a deepening visual transformation, and a new layer of how the world perceives you. The system is one-directional unless the player takes deliberate action to cleanse — and cleansing is expensive, non-trivial, and temporary.

| Mark | Corruption Ability | Visual Transformation | World Response |
|------|-------------------|-----------------------|----------------|
| Mark I — Touched | Enemies sense you from slightly further; minor Luminance drain resistance | Eyes shift — irises darken toward violet | Most NPCs unaffected; Ashen Choir members nod in recognition |
| Mark II — Stained | Breaking an enemy's Posture releases a small dark pulse that briefly disables nearby light sources | Veins become faintly visible beneath skin; shadow clings slightly longer when moving | Certain Pillar Warden NPCs refuse service; Ashen Choir offers minor discounts |
| Mark III — Darkened | Passive HP drain converts to Posture recovery — you hurt, but you don't stagger | Partial facial corruption; hair or skin shows necrotic patterning | Generic NPCs avoid proximity; Choir offers faction rank access; some bosses react differently |
| Mark IV — Hollowed Edge | Brief shadow form on taking lethal damage — a 3-second invulnerability window once per combat, after which you're mortal again | Body partially translucent at edges; enemies and players can see your Omen mark glowing | Most neutral NPCs will not interact; you are hunted by Warden squads in Ring One; Choir considers you sacred |
| Mark V — Convergent | Passive Luminance drain in your proximity; enemies targeting allies are briefly confused and may retarget toward you | Full visual transformation — your character becomes architecturally uncanny, echoing The Preserved aesthetically | You are a world event. Everything responds to you. NPCs flee or venerate. High-Luminance players actively seek to purge you. |

### Omen Accumulation Triggers

Omen is accumulated through both deliberate and incidental means. Understanding the triggers allows players to manage Omen intentionally — or to accelerate it, if the Choir path is their goal.

**Death.** Each death adds a partial Mark toward the next threshold. The amount scales with where you died — a Ring One death barely registers, a Ring Four death pushes significantly.

**Deep-zone dwell time.** Sustained presence in Ring Three and beyond passively accumulates Omen. This is not punishing — it's atmospheric. The deep dark changes you.

**Ashen Choir interactions.** Certain Choir quests, rituals, and exchanges directly add Marks. This is the fastest voluntary accumulation path and requires faction alignment.

**Aspect overuse.** Sustained use of Marrow abilities, or using Void phase abilities more than twice per engagement, creates Omen residue. This is designed to be a pressure valve — it rewards restraint without demanding it.

**Specific world events.** Certain discoveries in the Vael Depths, Memory Fragments of a particular type, and interactions with specific NPCs add or subtract Marks. These are hidden — finding them through play is the intent.

### Cleansing — The Cost of Retreat

Omen can be reduced, but never fully erased. Cleansing requires either Pillar Warden faction standing (ritual items that remove one Mark at escalating Resonance Shard cost) or specific consumables found only in Ring One — increasingly rare as the player advances.

Cleansing is intentionally expensive. It should feel like a real decision: do I lean into what the darkness is making me, or do I pay significantly to remain who I was? There is no wrong answer. But there is a choice.

> *A player who reaches Mark V and sustains it for a full in-game week earns the Ashen Record entry "Convergent." It's one of the rarest designations in the game and permanently marks that achievement even if the player later cleanses.*

### Omen in PvP

High-Omen players broadcast tells. Their silhouette is corrupted. Their Luminance signature is unusual — lower than their actual position would suggest. Experienced players learn to read Omen level from a distance. The result is that a Mark IV or V player in open-world PvP is always telegraphing their presence — powerful but visible.

The strategic tension: high Omen grants significant combat advantages but turns you into a target worth pursuing. Killing a Mark V Drifter awards substantial Resonance Shards and a Repute bonus. High-Omen players become the game's recurring bosses, organically, through the accumulation of other players who want them dead.

This is by design. The most corrupted Drifters in Nightbound are not safe. They are powerful. They are feared. And they are hunted. The dark costs something. It's also worth something.

---

## HOW THE PILLARS INTERACT

Aspect, Discipline, and Omen are not siloed. They create a three-dimensional identity space where no two players are likely to inhabit the same combination — and where the intersection of all three produces emergent gameplay that no single pillar produces alone.

### Sample Build Archetypes

| Aspect | Discipline | Omen Level | Emergent Identity |
|--------|-----------|-----------|------------------|
| Void + Ash | Silhouette | Mark II–III | **The Ghost** — nearly impossible to track or pin down. Ash trails mislead, Void phases through corners, Silhouette's Ghoststep makes them faster than they should be. Lethal in PvP; terrifying in PvE ambushes. |
| Ember + Gale | Resonant | Mark 0–I | **The Blitz** — aerial pressure with accumulating heat stacks, esoteric weapons amplified by Resonant, Ignition Draft synergy sets airborne enemies ablaze. Favors aggression and forward momentum above all else. |
| Tide + Marrow | Ironclad | Mark IV | **The Tide-Eater** — Marrow attrition combined with Ironclad's Tempered Stance creates something almost unkillable. Posture barely moves. HP drains slowly. Enemies find themselves fighting a wall that grows stronger as the fight continues. |
| Ash | Wayward | Mark 0 | **The Drifter** — maximally flexible, never optimal, always capable. The player who's been everywhere and committed to nothing. Reads as unthreatening. Often isn't. |
| Void + Marrow | Resonant | Mark V | **The Convergent** — end-state horror. Luminance drain in proximity, Marrow attrition, Void disruption of Posture recovery. Other players can see the glow from far away. They usually run. |

### Progression as Identity

The final purpose of the three pillars is to ensure that every Drifter in Nightbound is *legible*. Other players should be able to look at a character — their weapons, their Omen tells, their Aspect signature, their Discipline's physical bearing — and read something true about them. Who they are. What they've done. How they tend to fight.

This legibility is what transforms a progression system into a social system. When you recognize a high-streak Void + Silhouette player by the shimmer they leave and the way they drift slightly ahead of their own footsteps, you've acquired information that changes how you play. That recognition is the real reward of depth.

The Three Pillars aren't three separate customization menus. They're three lenses on a single identity. The Drifter you become after two hundred hours is a specific, coherent, and utterly unrepeatable answer to a question the game asks of everyone who enters Vael:

*What are you willing to become?*

---

> *"Something warm. Something that remembers you."*
> — Found written on a wall in the Vael Depths, author unknown