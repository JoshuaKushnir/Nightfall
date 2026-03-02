# NIGHTBOUND — DEPTH-1 EXPRESSION MOVES
### All Five Aspects · Five Moves Each · Balanced PvP/PvE Design
### Status: DESIGN DOC — pending GitHub issues before implementation

---

## DESIGN PRINCIPLES

Every move in this document was built against these constraints:

**Balance axis.** Each Aspect has a defined role, but all five must be viable in
both PvP and PvE. No Aspect is the "right answer" in every situation. Each has
a ceiling for skilled players and a floor for new ones.

**Move mix per Aspect.** Each set of five includes:
- 2 offensive moves (damage, posture pressure, or both)
- 1 defensive/reactive move (counter, shield, escape, or recovery)
- 1 self-buff move (amplifies your own capabilities for a window)
- 1 utility/proc move (sets up a status, applies a condition, enables combos)

**Talent integration.** Every talent must interact with at least one of:
Posture, HP, Breath, Momentum, Stagger/Break, airborne state, a status
condition, or another Aspect system. No talent is a flat damage % increase
in isolation.

**Status conditions referenced throughout (all pending implementation):**
- **Stagger** — target is in 0.8s vulnerability window, open to Break
- **Slow** — movement speed reduced, dash distance reduced
- **Exposed** — target takes +% posture damage from all sources for duration
- **Grounded** — target cannot jump, vault, or wallrun for duration
- **Silenced** — one random Aspect ability on cooldown for duration
- **Burning** — light continuous HP drain, posture recovery halved
- **Saturated** — target is wet; interacts with Tide/Ember cross-abilities
- **Weightless** — target is briefly airborne/launched
- **Dampened** — Momentum multiplier reduced to 1× and locked for duration

---

## 🌫️ ASH

**Identity:** Misdirection, patience, and information advantage.
**Strength:** Ash excels at controlling what opponents think is happening.
Best kit for mind games, escapes, and delayed payoffs.
**Weakness:** Ash has the lowest direct damage output of any Aspect.
Moves require setup or reading the opponent to maximize value. Straightforward
aggression with no deception is punished — Ash rewards the patient player.
**Air combat:** Moderate. Ash gains strong repositioning tools in the air
but no aerial damage amplifiers.

---

### ASH — Move 1: ASHEN STEP *(Offensive)*

**Type:** Gap closer / Deception opener
**Cast time:** 0.15s
**Mana cost:** 20
**Cooldown:** 5s

Dash forward up to 12 studs, leaving a static afterimage at your origin point.
The afterimage persists for 4 seconds, can be targeted and attacked by enemies,
and on destruction emits a blind flash (0.3s camera whiteout) for whoever
struck it. The dash itself deals light posture damage (15pts) on arrival.
The afterimage does not move, block, or attack — it is purely a decoy.

**Strength:** The blind flash punishes aggressive players who swing at the image
without thinking. Effectively a 4-second landmine. Very low cooldown relative
to effect potential.
**Weakness:** Low direct damage. No effect if opponents simply ignore the image.
Requires the opponent to swing at it to trigger the flash. Experienced players
learn to ignore it quickly.

| Talent | Interacts With | Description |
|---|---|---|
| **Hollow Echo** | Stagger | If the afterimage is hit while the attacker is in Stagger state, the blind flash duration doubles to 0.6s. Chains Stagger into extended vulnerability. |
| **Momentum Trace** | Momentum | If Ashen Step is cast at 2× Momentum or higher, the afterimage also mimics your last sprint direction for 1 second, creating a false movement vector before freezing. Harder to identify as a decoy at speed. |
| **Haunting Step** | Airborne | If cast while airborne, the afterimage spawns at your air position and falls slowly instead of freezing — a falling decoy that tracks toward the ground. Disrupts targeting in aerial engagements. |

---

### ASH — Move 2: CINDER BURST *(Offensive)*

**Type:** Point-blank burst / Posture stripper
**Cast time:** Instant (0s)
**Mana cost:** 20
**Cooldown:** 7s

Release a tight cone of compressed ash directly in front of you (6 stud range,
30° arc). High posture damage (35pts). Deals the Exposed status for 3 seconds
— target takes +20% posture damage from all sources. Negligible HP damage.
Has no cast time, which means it can be used during the wind-up frames of a
melee attack to cancel into it.

**Strength:** Instant cast makes it a true punish tool. Exposed status makes
the next hit, whether melee or another Aspect move, significantly more effective.
**Weakness:** Extremely short range. Requires being nearly inside the opponent.
No tracking. Can be dodged or blocked on reaction if telegraphed.

| Talent | Interacts With | Description |
|---|---|---|
| **Choking Veil** | Slow (status) | If Cinder Burst connects from behind the target (within a 120° rear arc), it also applies Slow for 2 seconds. Rewards positioning and flanking over direct confrontation. |
| **Ash Lung** | Breath | Targets hit by Cinder Burst have their Breath regen rate halved for 3 seconds. Disrupts the movement economy of Silhouette and high-mobility builds. |
| **Smothered** | Exposed + Break | If you Execute a Break on an Exposed target, the Break deals +15 additional HP damage. Cinder Burst + any posture pressure + Break is now a genuine combo chain. |

---

### ASH — Move 3: FADE *(Defensive)*

**Type:** Reactive escape / Repositioning
**Cast time:** 0.1s
**Mana cost:** 25
**Cooldown:** 12s

Instantly phase yourself into a brief partial transparency (not full invisibility —
you are visibly faded). For 1.5 seconds, all incoming attacks deal 80% reduced
posture damage and 50% reduced HP damage. At the end of the 1.5 seconds (or
if you attack, which cancels it early), you release a small ash exhale that
applies Slow to all targets within 4 studs for 1 second.

**Strength:** Exceptional "oh no" button. Best defensive tool in the Ash kit.
The exit slow punishes players who rush in expecting to follow up.
**Weakness:** Attacking cancels it — so you can't tank and fight simultaneously.
12 second cooldown is the longest in the Ash kit. Transparent, not invisible
— experienced players can still track and position on you.

| Talent | Interacts With | Description |
|---|---|---|
| **Ashen Shroud** | Airborne | If Fade is activated while airborne, you also gain a brief upward drift (small vertical float) that breaks lock-on targeting for the duration. Aerial escape tool. |
| **Exhale** | Slow + Posture | The Slow on Fade's exit now also applies Exposed (2s) in addition to Slow. The window after Fade becomes a setup window, not just a breather. |
| **Breath Reserve** | Breath | Activating Fade restores 20 Breath, regardless of your current pool. Incentivizes Fade as a mid-movement tool rather than pure panic button. |

---

### ASH — Move 4: TRACE *(Utility / Proc)*

**Type:** Marking / Information
**Cast time:** 0.2s
**Mana cost:** 15
**Cooldown:** 8s

Send a short-range ash tendril (10 studs, tracks toward nearest target). On hit,
marks the target with an Ash Trace for 10 seconds. While marked, you can see
their position through walls at close range (8 stud radius wallhack). The mark
is invisible to the target. Deals negligible posture damage (5pts) on hit.

**Strength:** Lowest mana cost in the Ash kit. Creates a continuous information
advantage that chains well into Ashen Step and Cinder Burst. Good PvE tool for
tracking enemies behind cover.
**Weakness:** Tiny damage. Opponents can step out of range and the wallhack
loses function. No combat effect beyond the information component. In open
environments with no cover, it provides nothing.

| Talent | Interacts With | Description |
|---|---|---|
| **Resonance Trace** | Living Resonance | If the marked target has an active Living Resonance streak, Trace also reveals their approximate HP percentage via HUD text for the duration. Directly counters the "tanky streak" playstyle. |
| **Burning Mark** | Exposed | If the marked target is already Exposed (from Cinder Burst), the Trace mark also increases all damage they take by 5% for the remaining Exposed duration. Stacking proc tool. |
| **Shadow Tendril** | Airborne | Trace can be cast vertically upward at a 45° angle to mark airborne targets. Standard horizontal cast cannot track airborne targets. |

---

### ASH — Move 5: GREY VEIL *(Self-Buff)*

**Type:** Offensive amplifier / Concealment
**Cast time:** 0.3s
**Mana cost:** 30
**Cooldown:** 18s

Wrap yourself in ash for 5 seconds. During this window, your dash leaves no
visible trail, your Aspect move animations are dampened (shorter startup
telegraphs), and all your posture damage is increased by 25%. At the end of
the 5 seconds, the ash releases in a burst that applies Dampened to all
targets within 5 studs (their Momentum resets to 1× and is locked for 2
seconds).

**Strength:** The posture damage buff makes Cinder Burst and Ashen Step
significantly more threatening during the window. Reduced telegraphs make
reads harder. Burst ending punishes anyone who stayed close.
**Weakness:** Longest cooldown in the Ash kit. Short window (5s) punishes
wasting it. No HP damage bonus. No effect at range.

| Talent | Interacts With | Description |
|---|---|---|
| **Veil Striker** | Momentum | If you deal a Break during Grey Veil, the cooldown is immediately reduced by 8 seconds. Rewards closing fights quickly inside the window. |
| **Silenced Approach** | Silenced (status) | When Grey Veil activates, any target within 5 studs is immediately Silenced for 1 second. Close-range opener that takes away a response tool immediately. |
| **Lingering Veil** | Slow | The exit burst now also applies Slow (2s) in addition to Dampened. Combined Slow + Dampened + momentum lock makes escape from Ash very difficult. |

---

## 🌊 TIDE

**Identity:** Resource denial, terrain weaponization, sustainable pressure.
**Strength:** Tide is the only Aspect that directly manipulates resources —
opponent Breath, Posture recovery, and positioning. The best kit for long
fights and punishing movement-heavy builds.
**Weakness:** All Tide moves have notable cast times. Tide is heavily
punished by aggressive, close-range opponents who don't give windows to
cast. No instant moves. Also, wet zone effects have zero value in PvE
against enemies that don't have Breath or Momentum.
**Air combat:** Weak. Tide is fundamentally a ground Aspect. All Tide moves
are weakened or unavailable against fully airborne targets.

---

### TIDE — Move 1: CURRENT *(Offensive)*

**Type:** Ranged knockback / Terrain weapon
**Cast time:** 0.3s
**Mana cost:** 20
**Cooldown:** 7s

Project a water surge 15 studs forward. On hit, knocks the target back 8 studs
and deals moderate posture damage (25pts). If the target collides with a wall
or obstacle during the knockback, they take bonus HP damage (20pts) and are
briefly Grounded (1.5s — cannot jump, vault, or wallrun).

**Strength:** Wall-killzone denial. Ring One terrain (close walls, ruins) makes
the bonus HP damage frequently applicable. Grounded status takes away Gale's
and Silhouette's core escape tools.
**Weakness:** 15-stud range feels long but the cast time means it must be read.
Can be sidestepped. No effect on airborne targets (the surge passes under them).
Grounded status has zero value in PvE against enemies that already walk.

| Talent | Interacts With | Description |
|---|---|---|
| **Riptide** | Airborne (counter) | Targets who dodge Current while airborne are instead knocked downward, applying Weightless (inverted — they slam into the ground, brief stagger). Anti-air counter for Gale/jump-heavy builds. |
| **Saturating Wave** | Saturated (status) | Current leaves a wet zone 4 studs wide along its path for 5 seconds. Targets moving through it gain Saturated. Saturated targets take +25% damage from Ember abilities (existing cross-Aspect interaction). |
| **Drowning Shore** | Breath | Targets who are at 25% Breath or below when hit by Current are also Dampened for 2 seconds (Momentum reset). Punishes Breath-exhausted opponents who are already overcommitted. |

---

### TIDE — Move 2: UNDERTOW *(Utility / Proc)*

**Type:** Pull / Setup
**Cast time:** 0.2s
**Mana cost:** 20
**Cooldown:** 8s

Pull target toward you over 8 studs, applying a brief Slow (1.5s) on arrival.
Light HP damage (10pts). If the target was moving away from you when pulled
(retreating), pull distance doubles to 16 studs and Slow duration increases
to 3 seconds. Does not work on airborne targets.

**Strength:** Hard counter to retreating opponents. Punishes distance-keeping
playstyles. Doubles as a positioning reset in PvE — drag enemies into a group
for follow-up.
**Weakness:** Completely ineffective against airborne targets. Opponents who
commit toward you gain nothing from its effects. Low damage. Has the shortest
effective range of any Tide move (target must be within 8 studs to pull).

| Talent | Interacts With | Description |
|---|---|---|
| **Flood Sense** | Saturated | Targets who are Saturated when Undertow hits take double the Slow duration. Saturated + Undertow becomes a 6-second Slow, effectively removing mobility from a target for a full engagement window. |
| **Tidal Lock** | Posture | After Undertow lands, your next attack within 2 seconds cannot be blocked — the target is off-balance from the pull. The anti-block window rewards immediate follow-up. |
| **Surface Tension** | Grounded | If the pulled target passes over a wet zone (created by Current or Saturated ground) during the pull, they gain Grounded instead of Slow. More punishing version that requires Current setup. |

---

### TIDE — Move 3: SWELL *(Defensive)*

**Type:** Reactive shield / Resource restoration
**Cast time:** 0.4s
**Mana cost:** 25
**Cooldown:** 14s

Encase yourself briefly in a water shell. For 2 seconds, all incoming posture
damage is reduced by 60%. At the end of the 2 seconds (or when the shell
is struck 3 times), the water releases and restores 20% of your maximum
Posture. Grants a minor push-back (3 studs) to any target within 2 studs
when the shell releases.

**Strength:** Excellent against Aspect-heavy opponents who rely on posture
pressure. The Posture restoration on release is the only self-healing on
a Posture bar in any Aspect kit at Depth 1. Punishes targets who rush in
expecting to Break you.
**Weakness:** 0.4s cast time is the longest wind-up in the Tide kit. If caught
during the cast, you take full damage. Does not protect HP at all — pure bleed
can still kill you during the shell. Highest mana cost in the kit.

| Talent | Interacts With | Description |
|---|---|---|
| **Tidal Surge** | Momentum | If Swell releases while you are at 2× Momentum or higher, the push-back range increases from 3 to 7 studs and applies Slow for 1 second. Punishes aggressive Momentum builds. |
| **Deep Breath** | Breath | Swell's 2-second window also fully restores your Breath pool. The defensive window is also a breath reset — enables movement burst immediately on release. |
| **Reflect Current** | Slow (incoming) | If you are Slowed when Swell activates, the Slow is transferred to all targets within 4 studs on activation. Counter-tool against Ash/Tide opponents who try to slow you first. |

---

### TIDE — Move 4: FLOOD MARK *(Utility / Proc)*

**Type:** Area denial / Status setter
**Cast time:** 0.25s
**Mana cost:** 15
**Cooldown:** 9s

Place a wet zone at a target location within 12 studs (8 stud radius). The
zone persists for 8 seconds. Targets standing in the zone gain Saturated
immediately and have their Posture regen rate reduced by 50% while inside it.
Saturated targets take bonus damage from Ember abilities. The zone itself
has no damage.

**Strength:** Area denial that directly targets Posture recovery. Best Tide
setup move for created Saturated status. Pairs with Current's terrain damage
and Undertow's enhanced effects. PvE: very strong against grouped enemies.
**Weakness:** Requires targets to enter or remain in the zone. Mobile opponents
simply step out of it. Cannot be placed directly on a target — requires
prediction. Purely tactical with no direct combat output.

| Talent | Interacts With | Description |
|---|---|---|
| **Stagnant Pool** | Grounded | Targets who take a hit (any source) while standing in a Flood Mark zone gain Grounded for 1 second. Any hit inside the zone triggers Grounded — severe positioning punishment. |
| **Rising Tide** | Posture | While standing in your own Flood Mark zone, your Posture regen rate is doubled instead of halved. Positional advantage that rewards fighting from your own terrain. |
| **Phantom Depth** | Airborne | Flood Mark zones pull airborne targets downward by 2 studs when cast directly below them, applying Grounded immediately on landing. Gives Tide a limited anti-air option. |

---

### TIDE — Move 5: PRESSURE *(Self-Buff)*

**Type:** Offensive amplifier / Sustained pressure
**Cast time:** 0.2s
**Mana cost:** 30
**Cooldown:** 16s

Enter a flowing state for 6 seconds. During this window, your melee attacks
cannot be parried (the parry window doesn't register against your strikes),
and all your Tide abilities apply Saturated on hit regardless of whether
they would normally do so. At the end of 6 seconds, you restore 15 Mana.

**Strength:** Parry immunity is a significant PvP tool — Silhouette and
Wayward builds that lean heavily on parrying are fundamentally disrespected
during this window. Saturated application on all abilities chains into
cross-Aspect combos. Mana restore on expiry makes it cost-effective.
**Weakness:** 0.2s cast time still means you need a moment to use it.
Long cooldown (16s). Against opponents not using parry, the parry immunity
component is wasted value. Doesn't help at all in PvE against most enemies.

| Talent | Interacts With | Description |
|---|---|---|
| **Current State** | Momentum | Activating Pressure grants 1 Momentum stack instantly (toward 3× cap). The buff and a Momentum start fire together. |
| **Flowing Form** | Slow (self) | Tide abilities cast during Pressure cannot trigger Slow on yourself (from terrain or opponent effects). Removes one vulnerability during your offensive window. |
| **Undertow Pressure** | Slow + Saturated | Undertow cast during Pressure applies Saturated and Slow simultaneously (they would normally require two separate casts to achieve this). Combo compressor. |

---

## 🔥 EMBER

**Identity:** Stack-based escalation, aggressive commitment.
**Strength:** The highest ceiling for sustained damage output. Ember builds
that are ahead in a fight accelerate — Heat stacks on the opponent and
Momentum working together create compounding pressure.
**Weakness:** Ember requires time and resources to reach peak effectiveness.
A cold Ember player (no stacks, no Momentum) is one of the weaker Aspects
head-to-head. Punished heavily by Posture breaks in the early fight before
stacks are built. All moves become more expensive mid-combo.
**Air combat:** Strong from above (diving), weak from below.
Ember's sprint acceleration gives it unique dive angles.

---

### EMBER — Move 1: IGNITE *(Utility / Proc)*

**Type:** Stack builder / Initiator
**Cast time:** 0.2s
**Mana cost:** 20
**Cooldown:** 5s

Charge forward 8 studs, applying 1 Heat stack to target on contact and
dealing light posture damage (15pts). Heat stacks decay after 6s if not
refreshed. At 3 stacks, target is Burning: light continuous HP drain
(5HP/s for 4s) and Posture recovery halved.

**Strength:** Shortest cooldown in the Ember kit. The stack engine. Most
fights begin and end with this move setting the board.
**Weakness:** Low direct damage. Stacks expire — a patient opponent who
avoids contact for 6 seconds resets the work. Easy to read at low range.

| Talent | Interacts With | Description |
|---|---|---|
| **Heat Transfer** | Burning | If target is already Burning, Ignite reapplies Burning and resets the 4s duration instead of stacking higher. Maintains Burning against healing/recovery builds. |
| **Torch** | Momentum | At 2× Momentum, Ignite applies 2 Heat stacks instead of 1. The movement investment is rewarded with double stack pressure. |
| **Ignition Chain** | Airborne | If Ignite connects mid-air (both you and target airborne), neither of you takes knockback from the collision — you both continue moving. Creates an aerial combo-extender. |

---

### EMBER — Move 2: FLASHFIRE *(Offensive)*

**Type:** AoE payoff / Stack detonation
**Cast time:** 0.15s
**Mana cost:** 25
**Cooldown:** 10s

Release heat burst in a 5-stud sphere. Moderate posture damage (20pts) to
all targets. Consumes all Heat stacks on every target hit, dealing bonus
HP damage per stack consumed (8HP per stack). After cast, Overheat activates
for 2s: Mana regen paused but melee damage +20%.

**Strength:** The AoE range means this can hit multiple opponents in group
fights. Stack consumption payoff scales up to 3 stacks × 8HP = 24 bonus HP
damage — significant. Overheat turns the immediate aftermath into a genuine
threat window.
**Weakness:** 5-stud range requires close proximity. Overheat prevents mana
recovery for 2s after an already mana-intensive sequence. Opponents with
no Heat stacks receive no bonus damage from the detonation.

| Talent | Interacts With | Description |
|---|---|---|
| **Flashpoint** | Momentum | If Flashfire is cast at 3× Momentum, range increases to 8 studs and Overheat duration extends to 3.5 seconds. Highest-risk version becomes the highest-reward version. |
| **Scorch Mark** | Saturated | Flashfire creates a 4-stud burning ground tile for 5s. Saturated targets entering the tile immediately gain Burning. Connects with Tide's Saturated cross-interaction. |
| **Thermal Feedback** | Posture | During Overheat, blocked hits also drain Posture (normally blocked hits deal 0 HP but do drain Posture via standard rules — Thermal Feedback makes Overheat attacks drain an extra +10 Posture per blocked hit). |

---

### EMBER — Move 3: HEAT SHIELD *(Defensive)*

**Type:** Reactive counter / Self-sustain
**Cast time:** 0.1s
**Mana cost:** 20
**Cooldown:** 12s

For 1.5 seconds, convert incoming HP damage to Posture damage instead
(effectively: you take no HP damage but take Posture hits at 150% of the
normal posture drain rate). At the end of the 1.5 seconds, restore 1 Heat
stack to yourself for each hit absorbed (max 3 stacks).

**Strength:** The only move in Ember's kit with a primarily defensive function.
Absorb hits and generate stacks from your own defense. The stack generation
on absorption means trading blows during Heat Shield is favorable if you
time the follow-up.
**Weakness:** 150% Posture drain on absorbed hits means you can be Staggered
through Heat Shield if the opponent commits fully. The stack restoration
only applies to yourself — does nothing toward applying stacks to the
opponent. 12s cooldown. 0.1s cast means it can be interrupted.

| Talent | Interacts With | Description |
|---|---|---|
| **Return Fire** | Heat Stacks | If Heat Shield absorbs 3 hits and converts all 3 into stacks, on expiry you release a small Ignite-equivalent pulse (no mana cost, no cooldown) — the absorbed pressure becomes instant offense. |
| **Ember Armor** | Burning (self) | While Heat Shield is active, if you are Burning, the Burning HP drain is paused. The defensive window also clears your own debuff timer. |
| **Thermal Mass** | Airborne | Heat Shield can be cast while airborne. If cast airborne, all absorbed hits during the window are converted to a single 4-stud burst on landing (similar to Flashfire, no stack consumption). |

---

### EMBER — Move 4: SURGE *(Self-Buff)*

**Type:** Momentum amplifier / Aggression amplifier
**Cast time:** 0.25s
**Mana cost:** 25
**Cooldown:** 14s

Gain immediate +1 Momentum stack and a 4-second sprint speed boost (+3 studs/s).
During the 4-second window, the first melee hit you land applies 1 Heat stack
to the target automatically, regardless of whether the hit was a light or heavy.
The speed boost ends if you take any damage.

**Strength:** Directly manipulates Momentum in a way no other move does.
The automatic Heat stack on first melee hit guarantees you've opened a
fight at 1 stack without spending Ignite mana. Best opener in the Ember kit.
**Weakness:** Speed boost cancels on damage — opponents who can land a
hit immediately punish the commitment. The Momentum stack boost can be
wasted if your chain breaks before you land the hit.

| Talent | Interacts With | Description |
|---|---|---|
| **Surge Feint** | Feinting | Surge's speed window allows your melee feints to apply Dampened to the opponent (Momentum reset) rather than just cancelling your own attack. Turns the fake-out into a debuff. |
| **Accelerant** | Breath | Surge restores 15 Breath on activation. Enables a movement burst immediately — sprint out of a bad position and Surge into a new angle simultaneously. |
| **Burning Approach** | Burning | If Surge is activated while a target within 8 studs is Burning, you gain 2 Momentum stacks instead of 1. Rewards fighting a target you've already pressured. |

---

### EMBER — Move 5: CINDER FIELD *(Utility / Proc)*

**Type:** Area control / Sustained pressure
**Cast time:** 0.3s
**Mana cost:** 30
**Cooldown:** 16s

Coat a 6-stud radius around your current position in embers for 6 seconds.
Targets entering the field take light HP damage over time (4HP/s) and gain
1 Heat stack per 2 seconds inside it. You do not gain Heat stacks from
your own field. Allies can stand in the field without effect.

**Strength:** The only non-direct stack application in Ember's kit. In PvE,
trapping enemy groups in the field while your allies attack is extremely
powerful. In PvP, the stack accumulation inside the field forces opponents
to move — it's both damage and repositioning pressure.
**Weakness:** You leave the field if you move, which you will in most fights.
The field does not follow you. Highly mobile opponents (Gale, Void) simply
never enter it. 6-stud radius is relatively small.

| Talent | Interacts With | Description |
|---|---|---|
| **Bonfire** | Burning | Targets inside Cinder Field who hit the 3-stack threshold and become Burning gain Grounded for 2 seconds at that moment. Combustion = rooted. |
| **Heat Sink** | Overheat | If Flashfire is cast while standing in your own Cinder Field, the Overheat duration is extended from 2s to 5s. Cinder Field becomes a Flashfire amplifier if you hold position. |
| **Draft** | Airborne + Gale synergy | Cinder Field creates an upward thermal column. You and allies in the field gain slightly increased jump height while inside it. Ember/Gale cross-build interaction. |

---

## 💨 GALE

**Identity:** Air superiority, spacing, kinetic punishment.
**Strength:** Gale is the strongest Aspect in aerial combat and the best
at controlling vertical space. Opponents who let Gale play from above
will lose badly. Movement chain combos are uniquely accessible to Gale.
**Weakness:** All of Gale's advantages require elevation or movement. A Gale
player who gets pinned on the ground loses their primary combat identity.
Gale has the worst defensive options of any Aspect — once caught without
airspace, the kit has very few answers.
**Air combat:** The strongest. Built for it.

---

### GALE — Move 1: WIND STRIKE *(Offensive)*

**Type:** Aerial initiator / Launcher
**Cast time:** 0.15s
**Mana cost:** 20
**Cooldown:** 6s

Dash toward target from up to 12 studs away, dealing moderate posture damage
(20pts) and launching both you and target slightly upward (Weightless for
0.5s). If cast while already airborne, launch height and posture damage both
increase by 50%. A second input (any attack) within 0.5s of landing applies
a bonus Momentum chain (as if a movement action occurred).

**Strength:** Excellent gap closer that works best from the air. The aerial
bonus is significant enough to reward building into the air before engaging.
Momentum chain on follow-up means every Wind Strike that converts into a
melee hit accelerates your Momentum build.
**Weakness:** At ground level against a grounded stationary target, Wind
Strike is noticeably weaker. Opponents who stay on the ground and play
defensively take significantly less from this move.

| Talent | Interacts With | Description |
|---|---|---|
| **Updraft** | Breath | Wind Strike restores 10 Breath on hit. Aerial chains that begin with Wind Strike sustain their own Breath cost. |
| **Gale Force** | Momentum | At 2× Momentum, Wind Strike's launch height increases and the 0.5s follow-up input window extends to 1.0s. More time to confirm the follow-up at high speed. |
| **Tempest Dive** | Airborne + HP | If Wind Strike is cast from above the target (Y position advantage of 5+ studs), it deals HP damage directly (20pts) in addition to posture. Dive-bomb is a genuine HP threat. |

---

### GALE — Move 2: CROSSWIND *(Utility / Proc)*

**Type:** Lateral control / Disorientation
**Cast time:** 0.1s
**Mana cost:** 15
**Cooldown:** 7s

Direct a wind blast perpendicular to your facing (toggled left/right at cast).
Light posture damage (12pts) and a lateral push (4 studs sideways). If target
is airborne, they instead receive a camera-disorienting spin and bonus HP
damage (15pts). If the lateral push sends target into a wall, they are briefly
Grounded (1s).

**Strength:** Lowest mana cost and one of the lowest cast times in the Gale
kit. In aerial combat against airborne targets, it's a genuine HP threat and
disorientation tool. Versatile in both PvP and PvE.
**Weakness:** Light damage at ground level. The lateral push direction (sideways)
is less intuitive than a forward knockback — opponents with good footing can
recover quickly. Wall-Grounded bonus requires terrain proximity.

| Talent | Interacts With | Description |
|---|---|---|
| **Slip Draft** | Grounded + HP | If Crosswind walls a target (wall-Grounded triggers), the bonus HP damage doubles to 30pts. High-risk, high-reward terrain play. |
| **Air Pocket** | Airborne + Cooldown | Casting Crosswind resets your mid-air directional redirect cooldown. Allows chaining: Wind Strike → Crosswind → redirect → Wind Strike (if cooldown recovered). |
| **Gust Warning** | Dampened | If Crosswind hits a target who is at 1× Momentum (no chain), it applies Dampened for 2s, locking them at 1× and preventing chain building. Stops momentum-reliant opponents from recovering their cadence. |

---

### GALE — Move 3: WINDWALL *(Defensive)*

**Type:** Barrier / Redirect
**Cast time:** 0.2s
**Mana cost:** 25
**Cooldown:** 13s

Create a wind barrier in front of you for 1.5 seconds. Incoming ranged Aspect
abilities (anything with a cast and travel component) are deflected sideways
rather than hitting you. Melee hits pass through but deal 50% reduced posture
damage while the barrier is active. On barrier expiry or when struck 2 times
by melee, releases a burst that pushes you backward 3 studs (auto-repositioning).

**Strength:** Hard counter to Tide's Current and Ash's Cinder Burst (both
ranged/medium range abilities). The auto-reposition on expiry prevents
opponents from immediately following up during the vulnerable cast recovery.
**Weakness:** Does not deflect all damage — melee still hits at half posture.
Does not work against airborne attacks (the wall has no vertical component).
13s cooldown is long. Not usable in the air — ground-only.

| Talent | Interacts With | Description |
|---|---|---|
| **Wind Whip** | Airborne | The push-back burst on Windwall expiry now launches you upward instead of backward (if you choose — toggled by holding jump at cast). Escape-into-air tool. |
| **Redirect** | Slow | Deflected Aspect abilities gain Slow properties when they hit the ground after deflection — the redirected projectile creates a Slow zone at impact. |
| **Eye of the Storm** | Momentum | While Windwall is active, you gain 1 Momentum stack (as if you performed a movement action). Defensive tool doubles as Momentum builder. |

---

### GALE — Move 4: UPDRAFT *(Self-Buff)*

**Type:** Movement amplifier / Air dominance
**Cast time:** 0.1s
**Mana cost:** 20
**Cooldown:** 10s

Launch yourself upward 8-12 studs instantly. Your next ability cast within
3 seconds while airborne deals 25% increased damage. Your mid-air redirect
is reset regardless of whether it was on cooldown. While in the air from
Updraft, your character glows faintly (visible to opponents — a tell). At the
peak of the Updraft launch, Breath is briefly suspended (no drain for 0.5s).

**Strength:** The fastest way to gain elevation in any Aspect kit. The ability
damage bonus makes any follow-up ability significantly more threatening from
above. Reset of redirect allows immediate course correction at the peak.
**Weakness:** The visible glow is a tell — experienced players know Updraft has
been used and that an ability is incoming. The 3s window means you must
commit to a follow-up quickly or waste the buff. No effect whatsoever if
used on the ground or in enclosed spaces with no vertical room.

| Talent | Interacts With | Description |
|---|---|---|
| **Storm's Eye** | Airborne + Posture | Abilities cast during Updraft's 3s window that deal posture damage deal an additional +15 posture on hit. Aerial posture pressure becomes breakable. |
| **Breath of Wind** | Breath | Updraft fully restores Breath at the apex of the jump. Aerial builds that chain Updraft into movement recover all Breath at the peak. |
| **Gale Dive** | Momentum + HP | After Updraft's 3s window, if you are still airborne and dive toward ground (moving downward at speed), landing grants 1 Momentum chain on contact. The return to ground is as good as the ascent. |

---

### GALE — Move 5: SHEAR *(Offensive)*

**Type:** Sustained aerial damage / Strafe tool
**Cast time:** 0.3s
**Mana cost:** 30
**Cooldown:** 14s

Deliver a sweeping wind arc in a wide horizontal plane (180° arc, 8-stud range).
Deals moderate HP damage (15pts) and high posture damage (30pts) to all targets
in arc. If any target is airborne, they instead take double HP damage (30pts)
and are Grounded on landing (2s). Cooldown reduced to 8s if cast while airborne.

**Strength:** Wide arc makes it very hard to avoid in tight spaces. The aerial
amplifier (double HP + Grounded) is brutal against Gale mirrors and Void
players who use aerial movement. Cooldown reduction while airborne is a
massive efficiency bonus for Gale's core playstyle.
**Weakness:** 0.3s cast time is Gale's longest. The wide arc is telegraphed —
experienced opponents will dodge backward out of arc range. At ground level
against grounded targets, HP damage (15pts) is low. High mana cost.

| Talent | Interacts With | Description |
|---|---|---|
| **Wind Cutter** | Momentum | At 3× Momentum, Shear's arc extends from 180° to 360° (full circle sweep). Highest Momentum reward in the Gale kit — full commitment becomes full dominance. |
| **Gale Shear** | Airborne (self) | Shear's cooldown reduction while airborne also applies retroactively — if you use Shear on the ground and become airborne within 2s after, the remaining cooldown is reduced to 8s. |
| **Condor** | Weightless | Targets who are Weightless (from Wind Strike or other launch) when hit by Shear remain airborne for 1.5 additional seconds, doubling the opportunity window for the Grounded landing punish. |

---

## 🌑 VOID

**Identity:** Disruption, isolation, and anti-comeback.
**Strength:** Void is the best Aspect at dismantling specific opponents.
It shuts down their options systematically — Silencing abilities, interrupting
Posture recovery, isolating targets from support. Void punishes players who
are good at the game harder than it punishes new players.
**Weakness:** Void requires knowing what your opponent can do and targeting
it. Against an opponent whose kit you don't understand, Void loses value.
Also, Void has below-average direct damage — you cannot simply brawl with
Void. Everything requires reading and intention.
**Air combat:** Moderate. Blink enables aerial repositioning but Void has no
aerial damage amplifiers. Void is not an aerial Aspect, but it can operate
there.

---

### VOID — Move 1: BLINK *(Utility / Proc)*

**Type:** Repositioning / Posture disruption
**Cast time:** 0.1s
**Mana cost:** 20
**Cooldown:** 4s

Phase-teleport to a target location up to 10 studs away, passing through any
geometry. On arrival, target's Posture recovery is interrupted and paused for
1 second. Your next melee hit within 1.5 seconds deals +30% posture damage.
Shortest cooldown in the Void kit.

**Strength:** The most flexible repositioning move in any Aspect kit. 4s
cooldown means it comes back quickly in sustained fights. Geometry phasing
is a unique traversal property no other Aspect has at this depth. The Posture
recovery interrupt is consistent value — always denies 1s of regen.
**Weakness:** No direct damage on cast. The melee follow-up bonus has a short
1.5s window. In open terrain with no geometry to phase through, the unique
value of the ability is partially lost.

| Talent | Interacts With | Description |
|---|---|---|
| **Nullpoint** | Stagger | If Blink is used within 3 studs of the target (close teleport), the Posture recovery interrupt extends from 1s to 2.5s. Against opponents who rely on fast Posture regen (Ironclad builds), this is a decisive tool. |
| **Phase Residue** | Slow | After Blink, your origin point leaves a spatial distortion for 1s. Any target that walks through it gains Slow for 1s. Punishes players who follow your teleport immediately. |
| **Void Slip** | Airborne | Blink can be cast while airborne. Standard cast while airborne grants an additional 4 studs of horizontal range (14 total). |

---

### VOID — Move 2: SILENCE *(Utility / Proc)*

**Type:** Ability lockdown / Anti-caster
**Cast time:** 0.15s
**Mana cost:** 20
**Cooldown:** 9s

Project a short void pulse toward target (8 studs range). On hit, Silences
the target for 3 seconds — one randomly selected Aspect ability is locked out.
Light posture damage (10pts). If the target is currently mid-cast when hit,
the ability they were casting is cancelled and their full cooldown is triggered
(they lose the cast and the cooldown resets against them — they cannot use
that ability again immediately).

**Strength:** Silence is the most targeted disruption in any Aspect kit.
Mid-cast cancellation is devastating — a Tide player about to cast Pressure
or an Ember player triggering Flashfire simply has it taken from them.
**Weakness:** Against opponents who are not casting and not ability-reliant,
Silence has minimal value (10pts posture is nearly nothing). Random ability
selection for the Silenced slot means it may or may not hit a key ability.
Cannot be aimed precisely at a specific ability.

| Talent | Interacts With | Description |
|---|---|---|
| **Echo Silence** | Silenced + Mana | When Silence suppresses a cooldown, you regain 15 Mana. Creates a sustain loop around reads. Every correct Silence is also a partial mana refund. |
| **Void Hunger** | Posture | If Silence hits a target who is currently Blocking (Blocking state active), it also breaks their block and deals full unguarded Posture drain on that frame. Bypasses the defensive stance entirely. |
| **Still Zone** | Silenced (area) | Silence leaves a void field at the impact point for 3 seconds. Any Aspect ability cast from within this field has its range reduced by 50%. Area denial for 3s after each Silence. |

---

### VOID — Move 3: PHASE SHIFT *(Defensive)*

**Type:** Evasion / Counter-positioning
**Cast time:** Instant (0s)
**Mana cost:** 25
**Cooldown:** 11s

Instantly phase out of your current position, becoming untargetable for 0.6s.
During this window, you cannot attack but cannot be hit by anything — Aspect
abilities pass through you, melee hitboxes miss, even targeted abilities
de-register. At the end of 0.6s, you reappear at your exact position plus
a 3-stud repositioning in the direction you were moving.

**Strength:** True invulnerability, even if only for 0.6s. The only Aspect
move that completely negates incoming damage. Instant cast — cannot be
interrupted. The 3-stud repositioning at exit means you never reappear
exactly where you phased, making it difficult to camp the reappearance.
**Weakness:** 0.6s is very short — requires anticipation, not reaction, to
be used well. Cannot attack during the window. 11s cooldown means poor
timing is severely punished. In PvE, enemy attack timing is more telegraphed
so it's stronger there than in PvP.

| Talent | Interacts With | Description |
|---|---|---|
| **Phase Echo** | Posture | Phase Shift restores 15 Posture on activation. The evasion window is also a micro-recovery. |
| **Void Exit** | Slow + Airborne | On reappearance after Phase Shift, if you are airborne (moved upward during the window), you emit a small spatial burst that applies Slow to targets within 4 studs. Turns Phase Shift into both evasion and a landing zone tool. |
| **Null State** | Stagger | If you Phase Shift during a Stagger window (i.e., you would have been broken), the Break is completely negated and you reappear without the Stagger state. Once per engagement only — the cooldown resets to base after this occurs. |

---

### VOID — Move 4: VOID PULSE *(Offensive)*

**Type:** Ranged disruption / Posture damage
**Cast time:** 0.2s
**Mana cost:** 20
**Cooldown:** 8s

Send a void pulse up to 12 studs forward (slow-moving projectile, 1s travel
time). On hit: high posture damage (30pts) and interrupts Posture regen for
2 seconds. If the target is in the process of performing a dodge when hit,
the dodge is cancelled (they take full hit and return to their pre-dodge
position). If the target is Silenced, the posture damage doubles.

**Strength:** High posture damage per cast. The dodge-cancel is a unique
punishment for predictable dodgers — it reads dodges and exploits them.
Against Silenced targets, becomes the highest posture damage move in the
Void kit.
**Weakness:** Slow projectile (1s travel time) can be sidestepped by any
moderately aware opponent. Requires Silence to reach full potential — depends
on combo setup. Against mobile opponents, this is the hardest Void move to
land reliably.

| Talent | Interacts With | Description |
|---|---|---|
| **Gravity Well** | Airborne + Grounded | Void Pulse, if it travels upward at 30°+ angle and hits an airborne target, applies Grounded on landing (2s). Anti-air snipe for players who dodge upward to avoid ground-level abilities. |
| **Resonance Drain** | Living Resonance | Void Pulse, on hit, reduces the target's Living Resonance streak timer by 5 seconds. Directly attacks Streak-reliant playstyles. |
| **Phase Chain** | Blink | If Blink was used within the last 2 seconds, Void Pulse fires instantly (no travel time — appears at the target instantly). The combo Blink → instant Void Pulse becomes an actual burst sequence. |

---

### VOID — Move 5: ISOLATION FIELD *(Self-Buff)*

**Type:** Control amplifier / Target isolation
**Cast time:** 0.3s
**Mana cost:** 30
**Cooldown:** 18s

Mark a single target within 12 studs. For 5 seconds, the marked target cannot
receive healing from any source, and any Aspect abilities they use have their
cooldown recovery slowed by 50% (abilities still work, they just come back
twice as slow). You gain 15% increased damage against the marked target for
the duration.

**Strength:** The most powerful ability in the Void kit against specific
opponents. In PvP, locking down a Swell-abusing Tide player or preventing
a crit Ember player from chaining Ignite back quickly is decisive. The
heal denial is particularly powerful against PvE boss mechanics or party
compositions with support.
**Weakness:** Single-target — useless in multi-target situations. Longest
cooldown in any Aspect kit (18s). The effects are entirely invisible to
the target — which also means they may not know to play around it. Has
no combat effect if the target doesn't use abilities frequently.

| Talent | Interacts With | Description |
|---|---|---|
| **Null Resonance** | Living Resonance | Isolation Field also removes the target's Living Resonance glow for the 5s duration. They cannot gain Shard bonuses or streak bonuses from kills made during the mark. |
| **Phase Lock** | Blink (self) | While Isolation Field is active, Blink's cooldown is halved (4s → 2s). The control window and your mobility become synchronized — you can reposition rapidly while the mark is running. |
| **Void Feeding** | Silenced | If Silence is applied to the Isolated target during the 5s window, the cooldown slow effect increases from 50% to 75% and the damage bonus increases from 15% to 25%. Isolation Field + Silence is the Void endgame combo. |

---

## BALANCE SUMMARY

The following table shows each Aspect's relative strength across key
dimensions. This is not mathematical — it is design intent, to be tested
and tuned in practice.

| | Burst Damage | Sustained Damage | Posture Pressure | Mobility | Defensive | Utility |
|---|---|---|---|---|---|---|
| **Ash** | Low | Low-Med | High | High (decoys) | High (Fade) | Highest |
| **Tide** | Low | Med | High | Low | Med-High (Swell) | High |
| **Ember** | Med-High | Highest | Med | Med | Low (Heat Shield) | Med |
| **Gale** | Med | Med | Med-High | Highest | Low-Med (Windwall) | Med |
| **Void** | Low-Med | Med | High | Med (Blink) | High (Phase Shift) | Highest |

**PvP matchup notes (pending playtesting):**
- Ash vs Ember: Ash's pacing and Fade deny Ember's stack buildup. Ember's
  Surge can occasionally break through. Even match in theory.
- Tide vs Gale: Tide's Grounded status is Gale's worst nightmare. But Gale
  played from above avoids the ground-zone tools. Very terrain-dependent.
- Void vs anything: Void's advantage scales with knowledge of the opponent.
  Against a first-time matchup, Void often underperforms. Against a familiar
  one, it wins decisively.
- Ember vs Gale: Ignition Draft synergy (airborne targets take bonus Ember
  damage) means Gale players who over-commit to aerial combat are punished.
  Gale who stays grounded loses the aerial identity. Good matchup tension.

---

## STATUS EFFECTS — IMPLEMENTATION REFERENCE

| Status | Source(s) in this doc | Mechanical effect |
|---|---|---|
| **Slow** | Ash (Choking Veil, Cinder Burst, Lingering Veil), Tide (Undertow, Flood Mark talent), Gale (Crosswind talent, Windwall redirect) | Movement speed −30%, dash distance −30% |
| **Exposed** | Ash (Cinder Burst, Fade talent) | All posture damage received +20% |
| **Grounded** | Tide (Current wall, talent), Ember (Bonfire talent), Gale (Shear airborne, Crosswind wall) | Cannot jump, vault, or wallrun for duration |
| **Silenced** | Void (Silence, Grey Veil talent) | One random Aspect ability locked for duration |
| **Burning** | Ember (Ignite × 3 stacks) | 5HP/s drain for 4s, Posture recovery halved |
| **Saturated** | Tide (Current, Flood Mark) | Takes +25% damage from Ember abilities |
| **Weightless** | Gale (Wind Strike) | Brief forced air state, 0.5s |
| **Dampened** | Ash (Grey Veil burst), Ember (Surge talent), Gale (Crosswind talent) | Momentum reset to 1×, locked for duration |

---

*Design doc authored: March 2026*
*No issues should be created for talents until Depth-1 move implementations*
*are complete and verified in Studio. Talent systems require move hooks to exist.*