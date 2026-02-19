# NIGHTBOUND — WORLD, COMBAT & SYSTEMS
### Design Expansion Document

<!--
COPILOT CONTEXT
================
This is the deep-design expansion for World, Combat, and Systems.
Impl files: MovementController.lua, MovementConfig.lua, CombatService.lua,
            ActionController.lua, PostureService.lua, DefenseService.lua,
            HitboxService.lua, NetworkService.lua, PlayerHUDController.lua,
            DataService.lua, PlayerData.lua, StateSyncService.lua

SPEC GAPS IN THIS FILE:
  MOVEMENT:
    - Breath drain rates per action: unspecced (needs numbers in MovementConfig)
    - Momentum ramp curve: capped at 3x, but ramp function undefined
    - Wall-run step count ("2-3 steps"): needs exact value + implementation
    - Stumble animation: asset not defined
  COMBAT:
    - Clash System: zero implementation; frame-perfect detection approach unspecced
    - Break damage formula: unspecced
    - Posture drain per attack type: no numeric table
    - Witnessing system: range, dwell duration, Codex entry data structure all unspecced
  DEATH:
    - The Between: revival range and UX flow unspecced
    - Ember Point: count limit, persistence (DataStore vs session), placement UX unspecced
    - Dimming debuff duration: described as "short" with no value
    - Shard loss-on-death formula: no values
  WORLD:
    - Server-wide Luminance tracking: data structure and update frequency unspecced
    - Drift Gate: activation sequence, cooldown, ownership data unspecced
    - Dimming Cycle: server-side scheduling, duration in real minutes, cadence unspecced
  FACTIONS:
    - NPC quest system: entirely undesigned
    - Faction switching mechanic: qualitative only
    - Unmarked "Unbound" stat bonus: no numbers
-->

---

## THE WORLD & CORE IDENTITY

### Vael — The Permanent Twilight

The continent of Vael exists in a state that took three centuries to become normal. The sun has not fully risen or set in living memory — not in the memory of the oldest NPC alive, not in any firsthand account. What's been lost is not just light. It's the entire psychological architecture that daylight builds: circadian rhythm, the sense of time passing in a way that matters, the understanding that tomorrow will look different from today.

The twilight is not dark. It is something worse — unresolved. Always the grey-gold of a moment just before sunset, or just after. The light has texture but no source. Shadows exist but don't move predictably. The world is readable enough to navigate but wrong enough to never feel safe in.

What remains to fill the void left by the sun is **Luminance** — ambient light emanating from the Solstice Pillars and, in smaller quantities, from the Drifters themselves. Luminance is both resource and identity marker. It drains in deep zones, can be sacrificed for others, and is the first thing enemies in the dark sense about you. High Luminance in Ring Four is a beacon. In Ring Five, it's a dinner bell.

### The Solstice Pillars — Why Cities Exist Where They Do

The Hearthspire was not built where it was built by coincidence. It occupies the site of the largest remaining Solstice Pillar — a structure of pre-twilight origin whose precise construction is no longer understood, which emits light strong enough to hold back the worst of what lives in the dark. The Pillar Wardens exist entirely to maintain and protect this structure.

There were more Pillars. The ruins of their sites are scattered across the Rings — dark places now, but architecturally distinct from the surrounding landscape if you know what to look for. Tide Communion players can sometimes detect residual energy at these sites. Void players can phase into structural echoes of what was there. These locations are among the most dangerous in the game and among the most lore-rich.

The Pillars are weakening. This is not a secret. The Wardens know. The Choir knows. The Wandering Court has mapped the rate of decline and the data is not encouraging. What nobody agrees on — what every faction is really arguing about beneath their surface ideology — is what the weakening means and what should be done about it.

### The Rings — A Geography of Darkness

The world radiates outward from The Hearthspire in concentric zones, each one darker and less understood than the last. This is not metaphor — the light literally fades the further you travel from the Pillar. The Ring structure serves several design functions simultaneously: it provides natural progression pressure, creates distinct visual and tonal identities for each zone, and makes the geography of the world legible to new players without requiring explanation.

**Ring Zero — The Hearthspire.** The city. Safe, warm, dense with social infrastructure. The Pillar's light is strong enough here that Luminance mechanics don't apply. This is the only place in Vael where people live without constant awareness of the dark. It produces a specific kind of insularity — Hearthspire citizens who have never left Ring One often don't fully believe in what Drifters describe beyond it.

**Ring One — The Verdant Shelf.** Forests and plains still receiving enough residual Pillar light to support life, though everything about that life is changed. Trees grow sideways toward The Hearthspire. Animals are nocturnal out of evolutionary habit even though full night never comes. The soil grows things but they're wrong — edible, sometimes, but not quite what they were. The first enemies here are recognizable. They telegraph. They exist to teach players the language of combat before the language becomes incomprehensible.

**Ring Two — The Ashfeld.** Dead forests and dried riverbeds and the infrastructure of a civilization that stopped functioning. The Ashfeld was once populated. The evidence is everywhere — roads, foundations, the shells of buildings that were built to last. What happened here wasn't violent. It was gradual. The light faded, the crops failed, the water dried up, and the people left or changed. The ones who stayed longest are the Hollowed. The Ashen Choir moved in after, drawn by something in the land itself.

**Ring Three — The Vael Depths.** The ruins of the old world, preserved in a state that is more disturbing than destruction would be. Tables still set. Clocks stopped. The architecture of normal life interrupted mid-motion and left. The Depths are where the lore of Nightbound lives in its densest form — the Memory Fragments, the Preserved, the specific geography that begins to reveal what the twilight actually is. Players who've been cataloguing the Umbral Codex start seeing patterns here. The answers are in the architecture, if you know how to read it.

**Ring Four — The Gloam.** Proper deep dark. Luminance drains passively for the first time. Player markers on the compass disappear. You navigate by sound, visual Aspect tells, and whatever you've learned about the terrain from previous runs. The Gloam is where the game becomes something different — quieter, more isolating, with a horizon that feels wrong. The Null is visible from here, on clear days, though "clear" in the Gloam means something different from what it means anywhere else.

**Ring Five — The Null.** The endgame zone. Luminance drains constantly. This is where the mystery resolves — not with a cutscene, but with what you find, what you fight, and what you choose at the end of it.

---

## THE DIMMING STRUCTURE — UPDATES AS WORLD EVENTS

Updates in Nightbound are not patches or expansions. They are **Dimmings** — world events that darken Vael incrementally, unlock the next Ring, and introduce new systemic depth alongside new content. The world is never fully revealed at launch. The horizon always exists.

This framing serves a purpose beyond branding. It ties the update cadence to the game's central narrative. The world is getting darker. The updates are the world getting darker. Players who are present for each Dimming experience the game's story as it happens rather than consuming it from a menu.

### The First Dimming — *Survival and Identity* (Launch)

The complete base game. The Hearthspire and Ring One. Players learn movement, combat, factions, and the core loop. The world feels complete but clearly edged — the darkness beyond Ring One is visible and impassable. NPCs speak of what's out there with the specific dread of people who've heard stories but know they'll never check.

The tone here is grounded and tense. The enemies are comprehensible. The threat is real but legible. The First Dimming establishes the grammar of the game. Everything after assumes fluency.

This Dimming ships when it's polished. Not before.

### The Second Dimming — *Corruption and Power*

Ring Two unlocks. The Ashfeld opens. The Omen system fully activates — Umbral Marks begin accumulating meaningfully and the first Omen paths become available. The Ashen Choir emerges as a major faction presence with their own questlines, their own economy, and their own interpretation of what's happening to the world. Morality in the game stops being simple. Marrow unlocks as an Aspect.

**New mechanic: Resonance Echoing.** In the Ashfeld, Aspect abilities leave environmental traces that linger briefly, creating dynamic battlefields where the terrain changes as a fight unfolds. An Ember user's sustained fight leaves burning patches that restrict movement. A Tide user fighting near a dried riverbed might actually restore water temporarily, creating a flowing obstacle. The environment becomes a participant in combat rather than a backdrop for it.

Resonance Echoing changes how veteran players approach the Ashfeld's fights. You stop fighting in spite of the terrain and start fighting through it.

### The Third Dimming — *History and Ruin*

Ring Three unlocks. The Vael Depths open. The Umbral Codex pays off significantly here — players who've been cataloguing lore start seeing the architecture of what happened to Vael. Named NPCs begin appearing who are clearly very old, offering fragmented answers that create more questions. The Depths are where the game stops being about survival and starts being about understanding.

**New mechanic: Memory Fragments.** Scattered throughout the Vael Depths are interactive echoes of moments that happened in specific locations. Touching them plays a brief first-person sequence from a perspective in the past. They are environmental storytelling delivered as gameplay — not cutscenes, not text walls, but experiential. Some of them are genuine historical records. Some are traps designed by the Ashen Choir to mislead players who are getting close to something true.

**New enemy category: The Preserved.** Former people who have been in the Depths so long they've become something architectural. They don't move until disturbed. When they do move, it's wrong — too fast, too still between bursts, using the ruins themselves as extensions of their attack pattern. They are the game's most disturbing enemy type because they're human in origin and inhuman in expression.

### The Fourth Dimming — *The Threshold*

Ring Four unlocks. The Gloam opens. Luminance drains passively for the first time. The Ashen Choir is everywhere in the Gloam and for the first time they seem afraid of something, not just devoted. A major lore revelation recontextualizes something established in the First Dimming — players who were paying attention will feel it land, and those who weren't will understand why they should have been.

**New mechanic: Dark Adaptation.** Players who spend significant time in the Gloam begin adapting — gaining low-light vision and Omen acceleration but also drawing the attention of creatures that sense Luminance like heat. High-Luminance players in the Gloam are paradoxically more at risk because they're visible in the dark. It forces builds to reconsider their identity. A high-Luminance Ember build that dominated Ring Three becomes a liability in Ring Four without deliberate adjustment.

**PvP in the Gloam.** Player markers on the compass disappear. You navigate and engage by sound, visual cues, and Aspect tells. The Gloam offers the most intense open-world PvP the game offers — every encounter is ambiguous until the moment of commitment, and the moment of commitment is often too late to reverse.

### The Final Dimming — *The Null*

Ships when the game is ready. When the playerbase has had time to truly inhabit every Ring, theorize collectively, build community knowledge, and feel the anticipation of something that's been visible on the horizon since Ring Four. The Null is the endgame zone. The mystery resolves — not with a cutscene, but with what you find, what you fight, and what you choose at the end of it.

The Null doesn't have a boss in the traditional sense. It has a **Convergence** — the largest world event the game has ever run, requiring the entire playerbase to coordinate, and whose outcome permanently and visibly changes The Hearthspire. The ending of Nightbound's first arc is a community event, not a solo achievement. What it means for the world to "end" here is something the playerbase decides together through collective action.

---

## MOVEMENT

> **Status:** 🔧 PARTIAL
> **Impl files:** `MovementController.lua`, `MovementConfig.lua`
> **What exists:** Sprint, dash (directional), lunge (combat nudge). Momentum tracked in `MovementController`.
> **Not yet implemented:** Wall-run, ledge catch, vault, slide, stumble animation, Aspect movement modifiers.
>
> **❓ REQUIRED BEFORE IMPLEMENTING remaining movement actions — define in `MovementConfig.lua`:**
> ```lua
> -- TARGET values (TBD by designer):
> BREATH_DRAIN_SPRINT    = ???  -- per second
> BREATH_DRAIN_DASH      = ???  -- per use
> BREATH_DRAIN_WALLRUN   = ???  -- per second
> BREATH_REGEN_GROUNDED  = ???  -- per second
> MOMENTUM_RAMP_RATE     = ???  -- multiplier gain per second of chained movement
> MOMENTUM_DECAY_RATE    = ???  -- multiplier loss per second when chain breaks
> MOMENTUM_MAX           = 3    -- confirmed
> WALLRUN_MAX_STEPS      = ???  -- "2-3 steps", pick one
> ```

### The Base Kit

Movement in Nightbound is the foundation that everything else is built on. The base kit — sprint, dash, wall-run, ledge catch, vault, slide — is designed to chain together fluidly. A sprint into a vault into a wall-run into a directional dash is a single committed movement sequence that a skilled player can execute instinctively after enough hours. The kit is learnable quickly and masterable slowly. That range is intentional.

**Breath** governs all movement actions. Sprinting, dashing, and wall-running drain Breath at different rates — wall-running the fastest, sprinting the slowest. Breath recharges fastest when grounded and stationary. Running out of Breath mid-sequence causes a stumble animation — punishing overcommitment without being unforgiving about it. The stumble is learnable. Players internalize Breath limits through repetition rather than through a UI meter demanding attention.

**Momentum** is the system's hidden depth. Maintaining speed through chained actions builds a momentum multiplier capped at 3x. High momentum increases dash distance and jump height, and gives melee strikes a slight damage bonus on contact during forward movement. Skilled movement isn't just about getting places quickly — it's a combat tool. The gap between a player who moves to fight and one who fights while moving is significant and learnable.

### Aspect Movement Modifications

Each Aspect subtly modifies movement identity without creating unfair advantages. These modifications are felt rather than read — they're the things other players notice about how you move before they can identify your Aspect.

- **Ash** — Dash leaves false afterimage trails that linger briefly. Can mislead enemies and players.
- **Tide** — Slides further. Momentum is preserved on wet terrain.
- **Gale** — One mid-air directional redirect per jump. Effectively extends any jump with a course correction.
- **Ember** — Slightly faster sprint acceleration. The gap to top speed closes faster.
- **Void** — Briefly phases through geometry corners on a cooldown. Creates movement options that don't exist for other Aspects.
- **Marrow** — Regenerates Poise faster during movement. Staying mobile accelerates recovery between hits.

### Environmental Movement

The world is built with traversal in mind. There is almost always a vertical path, a shortcut through ruins, a momentum line if you know the geography. Learning a region's movement language — its walls, its ledges, its wind currents, its water routes — is as rewarding as learning its combat encounters. Players who invest in regional knowledge move differently through those regions. They look like they've been there before because they have.

This is especially true of the Ashfeld's dried riverbeds (rideable with Tide Communion), the Vael Depths' collapsed architecture (vertical shortcutting that bypasses encounter rooms), and the Gloam's wind tunnels (Gale players can ride these between areas that are impassable on foot).

---

## COMBAT — PVP

> **Status:** 🔧 PARTIAL
> **Impl files:** `CombatService.lua`, `ActionController.lua`, `PostureService.lua`, `DefenseService.lua`, `HitboxService.lua`
> **What exists:** Attack pipeline, hitbox detection, Posture system skeleton, basic block/defense.
> **Not yet implemented:** Clash System, Condemned Mechanic, Living Resonance Streak, Dueling Grounds, Faction PvP, Last Rites.
>
> **❓ SPEC GAPS requiring numbers before implementation:**
> | Value | Status |
> |-------|--------|
> | Posture drain per attack type (light/heavy/Aspect) | Unspecced |
> | HP damage from a Break | Unspecced |
> | Clash follow-up window (stated: "half a second") | ✅ 0.5s |
> | Condemned trigger threshold (stated: 3+ attackers) | ✅ 3 |
> | Condemned Posture recovery rate bonus | Unspecced |

### The Core Framework: Posture and HP

Combat centers on two distinct health states that interact with each other in ways that create meaningful decision-making throughout every fight.

**HP** is your mortality threshold. It depletes from unblocked strikes and from Break attacks. When it hits zero, you die.

**Posture** is your structural integrity in a fight. It depletes when you block hits, take unguarded strikes, or absorb Aspect abilities. When Posture falls to zero, you stagger briefly — and a staggered target is open for a **Break**, a deliberate powerful strike that deals heavy HP damage and has distinct visual and audio signatures that other players nearby can hear.

The tension this creates is layered. You can sustain Posture damage while keeping HP high, then get Broken and suffer a HP consequence for what felt like absorbing the fight well. Alternatively, you can focus on stripping Posture quickly to force Break windows without engaging HP at all. Neither is universally correct. Build, matchup, and terrain all influence which approach is correct in a given fight.

Aspect abilities generally affect Posture more than HP. They're used to create Break windows rather than deal direct damage — with exceptions in deep Expression builds. This means Aspect users are Posture pressure specialists whose value is in enabling Break conditions, either for themselves or for allies.

### The Clash System

> **Status:** 📐 DESIGNED — Not implemented.
> **❓ SPEC GAP:** "Same frame" detection in Roblox requires a server-side approach (compare attack timestamps within a tolerance window, e.g. ±50ms). Spec the tolerance and the server event flow before implementing.

When two attacks connect within the same frame, a brief Clash moment fires. Both players push apart. There's a half-second window for a follow-up input — parry extension, counter-strike, or dash cancel. Successfully executing the follow-up deals bonus Posture damage and briefly staggers the opponent. Missing leaves you open.

Clash moments are the game's most dramatic beat and the highest expression of skill in combat. Novice players experience them as sudden interruptions in their intended sequence. Skilled players start playing *toward* them intentionally — reading opponent timing, deliberately matching attack frames to force a Clash at a moment they're ready for and the opponent isn't.

Learning to use Clashes is the difference between a good PvP player and a great one.

### PvP Systems

**The Condemned Mechanic.** If three or more players engage a solo target, that target gains Condemned status: passive Posture recovery boost, slight damage reduction, and improved tracking on melee attacks. It doesn't make you invincible against groups but it respects the solo player enough that a skilled one can survive, escape, or create enough chaos to turn a situation around. Nightbound doesn't reward zerging.

**The Living Resonance Streak.** The longer you survive without dying, the more a passive bonus called Living Resonance accumulates. It manifests as a faint warm glow around your character that other players can see — and mechanically it accelerates Shard gain, slightly boosts crafting quality, and improves rare drop chances from enemies. Veterans with a deep Living Resonance glow are immediately recognizable. Killing someone with a long streak rewards bonus Resonance Shards. Protecting your streak becomes a secondary objective in every encounter.

**Dueling Grounds.** Instanced arenas accessible from The Hearthspire and faction outposts. 1v1 and 2v2 formats, no loss penalty, purely for practice and building Repute. Repute is a visible stat on player inspection. High Repute players carry a subtle aura visible in the open world — a warning sign and a status symbol simultaneously. The best PvP players in Nightbound are legible, which creates a reputation economy that tracks real skill rather than time invested.

**Faction PvP.** Aligning with factions flags you in specific ways. Rival faction members are permanently marked to you in the open world beyond Ring One. This isn't forced PvP — you can still choose your engagements — but the world has political texture. Taking a Drift Gate controlled by a rival faction might mean running a gauntlet. Switching factions has a visible social cost: your previous faction's members remember, and their attitudes toward you shift accordingly.

**Last Rites.** When you know death is coming, a brief active input lets you choose what you leave behind. You can burn Resonance Shards to grant your killer bonus experience — a final act of respect or spite. Or you can channel your remaining Luminance into the ground, permanently brightening a small area and leaving a visible memorial mark with your name on it. Neither is mandatory. Both make death feel like it meant something.

---

## COMBAT — PVE

> **Status:** 🔧 PARTIAL — Dev dummy NPCs only (`DummyService.lua`, `DummyController.lua`).
> **Real enemy AI:** 🚫 FUTURE — implement after Ring One PvP loop is stable.
> **❓ SPEC GAP — Witnessing System:** Before implementing, define:
>   - Detection range (studs) for passive observation to register
>   - Minimum uninterrupted dwell time to earn a Codex entry
>   - Codex entry data structure (`{ creature, hint, timestamp, partial: bool }`?)
>   - Whether Witnessing progress persists across server sessions

### Enemy Design Philosophy

Every enemy in Vael has a readable identity. They telegraph. They have patterns. But those patterns are deep enough that they reward sustained engagement rather than immediate aggression. An enemy you've fought fifty times should feel learnable without feeling solved.

The **Witnessing** system formalizes this. Observing an enemy before engaging — watching their patrol loop, their idle behaviors, their responses to the environment — adds to your Codex entry for that creature and occasionally reveals a specific combat insight. Not a guaranteed strategy, but a tell. A vulnerability window, a preferred attack range, a behavior that precedes their most dangerous move.

This rewards patience in a game that also rewards aggression. Both approaches are valid. The Witnessing player has more information. The aggressive player has momentum. The tension between them is where good PvE play lives.

### The Enemy Roster

**The Hollowed.** Former Drifters and NPCs whose Luminance hit zero. They're echoes, running through the motions of their last moments. They have recognizable movesets — near-player-level ability usage, equipment that reflects who they were. Fighting a Hollowed feels deeply uncanny. Some are clearly repeating a fight they lost. Some are running from something that no longer exists. The Codex entries for Hollowed are written in a way that suggests the creature being documented was once a person with a name.

**The Duskwalkers.** Massive territorial creatures at Ring border zones. They don't try to kill you — they herd you toward darkness. They block paths, destroy light sources, create shadow zones, and use Aspect-adjacent abilities to manipulate your movement options. Fighting one head-on is possible but punishing. Learning their herding logic and using it against them — getting a Duskwalker to push you toward a route you wanted to take anyway — is how you actually engage with what they are rather than just surviving them.

**Threadweavers.** Deep-dark horror. They arrive at locations before players do and build trap infrastructure. You enter their area already at a disadvantage. Getting caught in a thread doesn't deal immediate damage — it roots you and drains Luminance. Fighting a Threadweaver is as much about navigating and dismantling its environment as dealing damage. Solo attempts are brutal. A coordinated two-player run where one distracts while one dismantles is deeply satisfying and reflects how the creature is actually meant to be engaged.

**The Ashen Choir.** The humanoid faction enemies, and the most human enemies in the game. They fight in coordinated groups with genuine morale — kill the leader first and weaker members flee; kill weaker members first and the leader becomes aggressive and empowered. They use Aspect abilities. They communicate during fights, sometimes in ways that give away their next move if you're listening. They are not mindlessly hostile. Choir enemies who recognize your faction alignment will sometimes react differently — wary rather than immediately aggressive if you're Choir-aligned, or specifically targeting you if you're Warden-aligned.

**The Preserved.** Found in Ring Three's ruins. Formerly human, now architectural. They don't move until disturbed. When they do move, it's wrong — too fast, too still between bursts of motion, leveraging the ruins around them as part of their attack pattern. A Preserved enemy in an open courtyard is manageable. A Preserved enemy in a collapsed building it's using as an extension of itself is one of the most dangerous encounters in Ring Three. The Witnessing system is particularly valuable here — observing a Preserved before disturbing it reveals its integration with the local environment.

**The Vaelborn.** Ring Four creatures that appear to have emerged from the twilight itself. They have no clear biology. No analogue to anything in the shallower Rings. They react to Luminance like prey reacting to predators — high-Luminance players draw their attention from further away. They are genuinely alien in behavior, attacking in ways that take time to parse even after multiple encounters. The Witnessing system is most valuable here. A fully Witnessed Vaelborn is still dangerous. An un-Witnessed one is terrifying.

### Bosses

Bosses are story-gated rather than level-gated. You encounter them by following threads — talking to NPCs, finding specific items, Witnessing the boss in a non-combat context first. This pre-encounter phase can be skipped but rewards those who engage: the boss might acknowledge you, might be slightly afraid, might be more aggressive because you've learned too much.

Every boss has a **second form** that triggers around 40% HP. Not a health refill — a behavioral shift. The arena changes. New mechanics activate. Players who've never seen the second form before experience genuine surprise, and the game's design around boss fights deliberately withholds strategy documentation to protect that surprise. The community builds the knowledge base themselves, which creates a shared experience of discovery rather than a menu of solutions.

### Convergence Events — World Bosses

The server's collective Luminance level is tracked. If the playerbase is struggling — too many deaths, too much time in deep zones, too many Hollowed emerging — a Convergence event triggers. A massive entity surfaces and begins moving toward Ring One, threatening The Hearthspire.

Every player on the server is notified through environmental tells before any UI prompt. The sky changes. NPCs panic. The Duskwalkers flee inward. You know something is happening before the game tells you what.

Defeating a Convergence entity requires coordination between PvP and PvE players who might otherwise be antagonistic to each other. It drops the game's best materials and restores server Luminance. Failing one — which is possible — has lasting consequences for that server's state until the next cycle allows recovery.

---

## DEATH & THE INCENTIVE TO SURVIVE

> **Status:** 📐 DESIGNED — Not implemented.
> **Impl files (target):** `DataService.lua`, `PlayerData.lua`, new RemoteEvents in `NetworkTypes.lua`
> **❓ SPEC GAPS requiring decisions before implementation:**
>   - **Shard loss formula:** flat | % of current Shards | scaled by Ring? — undefined
>   - **Dimming debuff duration:** "short real-time window" — pick a number (suggested: 5 minutes)
>   - **Ember Points:** Max count per player? Session-only or DataStore-persistent?
>   - **Revival (The Between):** How does the reviving player see and trigger the prompt? Range in studs?
>   - **The Between timer (stated: 30 seconds):** ✅ confirmed

### The Between

When you die, you enter a brief state called **The Between** — a liminal, desaturated version of wherever you fell. You can see the world around your corpse, faintly, like looking through fogged glass. You have roughly 30 seconds here. Other players can see a faint marker where you fell and can choose to *revive* you at the cost of some of their own Luminance — a genuine act of sacrifice.

The revival mechanic creates social bonds that no other system in the game produces. Being revived by a stranger is memorable. Being revived by someone you've been antagonistic toward is a relationship-defining moment. Choosing to revive someone in a dangerous zone is a statement about who you are in this world. The Luminance cost is real enough that it's never automatic.

If nobody revives you, or the timer runs out, you respawn at your last **Ember Point** — a manually placed anchor that can be repositioned at rest locations throughout each Ring.

### What You Lose

Death takes Resonance Shards, some consumables, and applies a temporary **Dimming** debuff — your Luminance cap is reduced for a short real-time window. This means you're slightly more vulnerable and restricted immediately after dying, which creates pressure without cruelty. The window is short enough to survive but long enough to matter.

What you never lose: your Aspect, your Discipline investment, your weapons, your Omen progress, or your Ashen Record. The permanent scaffolding of your character is safe. Only the in-flight currency is at risk.

### The Streak

The **Living Resonance Streak** is the game's primary incentive to survive beyond the simple desire to avoid dying. The longer you survive without dying, the more the streak accumulates, manifesting as a visible warm glow that other players can see and read. Mechanically, it accelerates Shard gain, boosts crafting quality, and improves rare drop chances.

The streak transforms survival into a visible, social, competitive thing. Your history is legible on your body. The glow announces how long you've been alive. Other players treat you differently — with respect, with wariness, or with the specific greed of someone who knows killing you yields bonus Shards.

### Last Rites

If you know death is coming — cornered, overwhelmed, running out of Breath with too many enemies between you and any exit — a brief active input triggers Last Rites. You choose what you leave behind.

**Burn your Shards** to grant your killer a bonus experience reward. It's a final act that makes your death feel authored. An acknowledgment of the fight.

**Channel your Luminance** into the ground, permanently brightening a small area of the world slightly and leaving a visible memorial mark with your name and time of death. These marks accumulate across Vael over time — a record of where Drifters fell. In areas of heavy combat or particular danger, clusters of memorial marks tell their own story.

Neither option is required. Both transform death from a UI state into a narrative moment.

---

## META PROGRESSION — THE ASHEN RECORD

> **Status:** 📐 DESIGNED — Not implemented.
> **Impl files (target):** `DataService.lua` (separate account-scope DataStore key), `PlayerData.lua` (ashenRecord field)
> **❓ SPEC GAPS:**
>   - Ashen Record DataStore schema: define the table shape before implementing
>   - Echoes: illustrative list only — need the **complete** unlock table with trigger conditions
>   - Umbral Codex entry format: `{ id, name, category, text, unlockCondition, unlockedAt }` or similar — unspecced
>   - Cosmetics: asset pipeline and unlock-condition table entirely undefined

### What the Record Is

The Ashen Record is your account-level history. It persists completely across deaths and even full character resets. It tracks everything: enemies witnessed and catalogued, bosses defeated, factions aligned with, regions explored, players dueled, and total survival time across all runs.

The Record is visible to other players when they inspect you. It functions as your real identity in the world — the thing that persists when your character doesn't. A player whose Record shows three complete character runs, two Convergence participations, and Mark V Omen once sustained for a full in-game week is telling a story about themselves through that Record without a word of explanation.

### Echoes — Persistent Minor Unlocks

The Ashen Record grants **Echoes** — passive minor unlocks that carry into new characters. These are deliberately kept small. Starting with slightly more Breath. Unlocking a second Ember Point slot earlier. Having one additional Aspect option available during character creation. Getting a marginal Luminance bonus in regions you've previously explored.

Echoes don't make new characters powerful. They make them *slightly more informed*. The advantage they provide is in the five minutes after character creation, not the five hundred hours after. The intent is to reward veteran players without creating a gap between new and experienced players that discourages new players from engaging.

### Cosmetics

Deaths, streaks, boss kills, and exploration milestones unlock visual items — character markings, weapon trails, Drift Gate animations, memorial stone designs — that persist forever and can never be lost. These are entirely non-combat and non-stat affecting. They are purely expressive, but they are the most visible sign of a player's history in the world.

The cosmetics system is designed around one principle: the rarest-looking characters should be the ones who have done the hardest things, not the ones who have spent the most money. Cosmetics are earned through achievement, never purchased. A character wearing the visual marks of Mark V Omen sustained, a Soulbound weapon, and a First Convergence participation badge is wearing a biography.

### The Umbral Codex

A meta-account book of lore, creature entries, faction histories, and world fragments collected across all characters. It fills in over time and is purely narrative reward — no stats, no unlocks, just knowledge and context.

The Codex serves the players who want to understand Vael deeply. Its entries accumulate across characters and runs, meaning a player on their third character is reading a Codex that their first two characters built. Longtime players have access to something genuinely exclusive: not power, but a depth of understanding about the world that newer players haven't earned yet.

Some Codex entries can only be filled by specific Aspect interactions with the environment. Some require surviving specific encounters without dying. Some require choosing to spare rather than kill specific enemies. The Codex rewards the kind of attention to the world that the game is built to encourage.

> *Your character is temporary and mortal. You, as a player, are accumulating something real.*

---

## FACTIONS

### Design Philosophy

Factions in Nightbound are not alignment sliders. They are not good and evil. Each faction has a coherent worldview that makes internal sense — a genuine response to the facts of life in Vael that a reasonable person could hold. Aligning with one is a statement about what kind of Drifter you are. What you believe about the dark. What you're willing to do to survive it.

The game never tells you a faction is wrong. It shows you what each one does and lets you decide what that means.

### The Pillar Wardens

Devoted protectors of The Hearthspire and the Solstice Pillars. They believe survival means holding the line — maintaining the light that exists rather than seeking new light elsewhere. Conservative, militaristic, and deeply suspicious of Omen-marked Drifters, whom they view as a corruption risk to the city they protect.

The Wardens are not wrong about what they're protecting. The Pillar is real. The threat is real. Their methods — surveillance, restriction, the systematic exclusion of the Omen-marked — are the methods of people who have accepted that survival requires sacrifice. They've decided who gets sacrificed.

**What alignment gives you:** The most Drift Gate access in the game. The best armor crafting. NPC trust in most civilian contexts. Certain enemies de-aggro. Cleansing rituals for Omen reduction, available at escalating cost.

**What alignment costs you:** The Ashen Choir actively hunts you. High-Omen players and Choir-aligned Drifters treat you as an enemy. You are locked out of Choir faction questlines and the Marrow knowledge they uniquely hold.

### The Wandering Court

A loose confederation of traders, explorers, and information brokers who have decided the only way to understand the twilight is to walk toward it. Politically neutral on almost everything. Diplomatically maintaining contact with every other faction, including the Ashen Choir. The Court believes information is more valuable than ideology.

Aligning with the Court doesn't mean you share their values — it means you've found them useful. They're the faction that most welcomes Drifters who haven't made up their minds yet, and the faction most likely to use you for something without telling you exactly what it is.

**What alignment gives you:** Access to the best market networks in the game. Unique movement-enhancing items. First access to Memory Fragments in Ring Three before other factions can reach them. A diplomatic buffer that makes most faction hostilities slightly slower to activate toward you.

**What alignment costs you:** No combat faction advantages. The Court doesn't fight on your behalf. If you get into trouble with the Wardens or the Choir, the Court's neutrality means they won't help. Alignment with the Court reads as unaffiliated to enemies — you benefit from no faction's protection.

### The Ashen Choir

Believers that the dying sun is mercy. The Choir's theology holds that the twilight is not catastrophe but completion — that the world before was too bright, too exposed, and that what's happening now is the natural endpoint of something that was always going to happen. They don't mourn the light. They welcome its passing.

They are not mindlessly evil. They have philosophy, hierarchy, genuine community, and a warmth toward each other that is almost entirely absent from the other factions' internal cultures. They welcome Omen-marked Drifters with open arms — the more marked, the more revered. They understand something about the dark that the other factions refuse to look at directly.

**What alignment gives you:** Omen-accelerating items that make the Choir path faster and more powerful. Exclusive Marrow Aspect knowledge unavailable elsewhere. Ring Two territory control and the economic advantages that come with it. Reverence for high-Omen characters that translates into real in-game support.

**What alignment costs you:** A permanent visual mark that other faction members identify immediately. Pillar Wardens treat you as an active threat. Civilian NPCs become harder to interact with. You are visible. You have chosen to be visible. The Choir path is the most difficult and most rewarding faction path in the game.

### The Unmarked

Players who refuse to align with any faction. This is not a passive choice — it is an active decision to opt out of the social infrastructure that factions provide. Unmarked players lose access to faction-specific crafting, gate access, and the diplomatic protections that faction membership provides.

What they gain is **Unbound**: slightly better stats in all areas at the cost of everything the factions offer. The math on Unbound is not obviously worth it. Choosing to be Unmarked is a statement. Other players read it as either principled or dangerous.

The Unmarked identity is also the most flexible — they can engage with faction questlines to a limited degree without committing, and they're the only players that every faction treats with baseline neutrality rather than ally-or-enemy framing. The information brokers of the Wandering Court especially appreciate Unmarked Drifters, finding them useful precisely because they belong to no one.

---

## GEOGRAPHY & WORLD SYSTEMS

### Drift Gates — The Politics of Travel

There are no mounts in Nightbound. Fast travel exists but is gated behind faction standing. Drift Gates are ancient structures that still function, maintained by NPC factions — each faction controls certain gates, and access to those gates is determined by your standing with that faction.

Early in the game, you're walking the world and learning it intimately. The travel time is a feature. You learn the geography, the enemy distribution, the movement routes, the shortcuts — information that matters when you're dying too far from an Ember Point and need to know the fastest walking route out.

Later, you're choosing which factions to align with, which determines which gates you can use, which determines which regions you can reach efficiently. This creates a geography of loyalty — where you can go quickly tells other players something about who you've aligned with.

### Dimming Cycles — Seasonal Events

Seasons are replaced by **Dimming Cycles** — periodic events where the world measurably darkens for several in-game days. During a Dimming Cycle, enemy behavior changes, new creatures emerge, and certain items and crafting materials only exist in this window.

Dimming Cycles create a natural rhythm of tension and release for the entire playerbase. They're the game's calendar. Players organize around them, prepare for them, share strategies for surviving them. The materials they offer create economic demand that doesn't exist outside the window, making Dimming Cycle participation economically meaningful even for players who don't need the challenge of the darkened world for its own sake.

---

> *"The sun didn't die. It's still there — somewhere behind all of this. You can feel it if you stand very still in the Verdant Shelf at the right moment and close your eyes. Something warm. Something that remembers you. Keep moving toward it. Even if moving toward it means going the wrong direction for a very long time."*
>
> — Found written on a wall in the Vael Depths, author unknown