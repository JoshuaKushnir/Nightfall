<!--
COPILOT CONTEXT — READ THIS FIRST
==================================
Project: Nightbound (repo: Nightfall) | Engine: Roblox via Rojo | Language: Luau

CODEBASE MAP — Design concept → source file(s):
  Combat (Posture/HP/Clash/Break/Hitbox) → CombatService.lua, ActionController.lua, PostureService.lua, DefenseService.lua, HitboxService.lua
  Movement (Breath/Momentum/Dash/Sprint)  → MovementController.lua, MovementConfig.lua
  Abilities (Aspect abilities)            → AbilitySystem.lua, AbilityRegistry.lua, abilities/*.lua
  Networking (RemoteEvents/Functions)     → NetworkService.lua, NetworkController.lua, NetworkProvider.lua, NetworkTypes.lua
  State machine                           → StateService.lua, StateSyncService.lua, StateSyncController.lua
  Weapons                                 → WeaponService.lua, WeaponController.lua, WeaponRegistry.lua, WeaponTypes.lua, weapons/*.lua
  Player data / DataStore persistence     → DataService.lua, PlayerData.lua
  UI / HUD                                → PlayerHUDController.lua, CombatFeedbackUI.lua, UIBinding.lua
  Animation                               → AnimationLoader.lua
  Dev/test NPCs                           → DummyService.lua, DummyController.lua, DummyData.lua

IMPLEMENTATION STATUS KEY (used inline throughout this doc):
  ✅ IMPLEMENTED  — exists and functional in codebase
  🔧 PARTIAL      — skeleton/stub exists, needs work
  📐 DESIGNED     — fully designed, not yet coded
  ❓ UNSPECCED    — mentioned in vision, mechanic not yet designed
  🚫 FUTURE       — planned for a later Dimming, do not implement yet

KNOWN SPEC GAPS (holes — see details in relevant sections below):
  1.  NPC/quest system — no mechanic designed
  2.  UI/HUD layout   — no screen layout spec
  3.  Server architecture / instancing — unspecced
  4.  Onboarding/tutorial flow — unspecced
  5.  Player-to-player trading mechanic — unspecced
  6.  Weapon weight classes — unnamed/undetailed
  7.  Tuning numbers — Breath costs, Shard loss formula, Momentum ramp all missing
  8.  Resonance Groove depth thresholds — no use-hour targets
  9.  Witnessing system mechanic — range/duration/Codex output unspecced
  10. Final Dimming / Null Convergence gameplay — narrative placeholder only
  11. Revival (The Between) — initiating player UX unspecced
  12. Ember Points — quantity, persistence, respawn UX unspecced
  13. Faction switching — no mechanical cost spec
  14. Audio system — entirely undesigned
-->

# NIGHTBOUND — COMPLETE GAME DESIGN DOCUMENT

-----

## THE WORLD & CORE IDENTITY

Nightbound exists in a world called **Vael** — a continent caught in permanent twilight. The sun hasn’t fully risen or set in three centuries. Nobody alive remembers daylight. What they know is The Hearthspire, the last functioning city built around one of the world’s remaining **Solstice Pillars** — ancient structures that emit artificial light strong enough to hold the darkness back. The pillars are weakening. Everyone knows it. Nobody agrees on what to do about it.

The world radiates outward from The Hearthspire in concentric Rings. Each Ring is darker, more dangerous, and less understood than the last. The players are **Drifters** — people who have been marked by the twilight in some way, giving them an unusual resilience that ordinary citizens don’t have. This is the in-world justification for why you can die and return, why you accumulate power, and why NPCs treat you as something between a hero and an omen.

The underlying mystery is simple in premise and deep in execution: something is eating the light, it has been for three centuries, and it is patient. The further into the Rings you go, the more you realize it might not be a monster. It might be a *decision* someone made a long time ago.

-----

## THE DIMMING STRUCTURE — UPDATES AS WORLD EVENTS

Updates are called **Dimmings**. Each Dimming darkens the world slightly, unlocks the next Ring, and introduces new systemic depth alongside new content. The world is never fully revealed at launch. The horizon always exists.

### THE FIRST DIMMING — *Survival and Identity* (Launch)

The Hearthspire and Ring One. The complete base game. Players learn movement, combat, factions, and the core loop. The world feels complete but clearly edged — the darkness beyond Ring One is visible and impassable. NPCs speak of what’s out there. The tone is grounded and tense. This Dimming ships when it’s polished, not before.

Ring One contains the **Verdant Shelf** — forests and plains that still receive enough residual light to support life, though it’s changed. The trees grow sideways toward the light. Animals are nocturnal out of ancient habit even though full night never comes. The first enemies here are recognizable, grounded, and serve as a tutorial for the deeper horrors ahead.

### THE SECOND DIMMING — *Corruption and Power*

Ring Two unlocks. The **Ashfeld** — a vast region of dead forests, dried riverbeds, and crumbling infrastructure from the pre-twilight world. The Omen system fully activates. Umbral Marks begin accumulating meaningfully and the first Omen paths become available. The Ashen Choir emerges as a major faction presence. Morality in the world stops being simple. A new Aspect — **Marrow** — unlocks, tied to the corruption of living things.

New mechanic introduced: **Resonance Echoing** — in the Ashfeld, Aspect abilities leave environmental traces that linger briefly, creating dynamic battlefields where the terrain changes as a fight unfolds. An Ember user’s sustained fight leaves burning patches. A Tide user fighting near a dried riverbed might actually restore water temporarily. The environment becomes a participant.

### THE THIRD DIMMING — *History and Ruin*

Ring Three unlocks. The **Vael Depths** — the ruins of the old world. Cities that existed before the twilight, preserved in an eerie state. Not destroyed, just… stopped. Tables still set. Clocks frozen. The people gone or transformed. The Umbral Codex pays off here significantly — players who’ve been cataloguing lore start seeing the architecture of what happened. Named NPCs begin appearing who are clearly very old, offering fragmented answers.

New mechanic: **Memory Fragments** — scattered throughout the Vael Depths are interactive echoes of moments that happened in specific locations. Touching them plays a brief first-person sequence from a perspective in the past. They’re environmental storytelling delivered as gameplay. Some of them are clues. Some are traps designed by the Ashen Choir to mislead.

New enemy category: **The Preserved** — creatures that were people before the twilight and have been in the Depths so long they’ve become something architectural. They don’t move until disturbed and then they move wrong — too fast, too still between movements, using the ruins themselves as part of their attack patterns.

### THE FOURTH DIMMING — *The Threshold*

Ring Four unlocks. The **Gloam** — proper deep dark. Luminance drains passively here for the first time. You can see The Null on the horizon. Something has been sending signals. The Ashen Choir is everywhere and for the first time they seem afraid of something, not just devoted. A major lore revelation recontextualizes something from the First Dimming — players who were paying attention will feel it land.

New mechanic: **Dark Adaptation** — players who spend significant time in the Gloam begin adapting, gaining low-light vision and Omen acceleration but also drawing the attention of things that sense Luminance like heat. High-Luminance players in the Gloam are paradoxically more at risk because they’re visible in the dark. It forces builds to reconsider their identity at the edge of the world.

New PvP wrinkle: in the Gloam, player markers on the compass disappear. You navigate and engage by sound, visual cues, and Aspect tells. It’s the most intense PvP the game offers.

### THE FINAL DIMMING — *The Null*

Ships when the game is ready. When the playerbase has had time to truly inhabit every ring, theorize, build community knowledge, and feel the anticipation. The Null is the endgame zone. Luminance drains constantly. The world’s core mystery resolves — not with a cutscene, but with what you find, what you fight, and what you choose at the end of it.

The Null doesn’t have a boss in the traditional sense. It has a **Convergence** — the largest world event the game has ever run, requiring the entire playerbase to coordinate, and whose outcome permanently and visibly changes The Hearthspire. The ending of Nightbound’s first arc is a community event, not a solo achievement.

-----

## PROGRESSION

> **Status:** 📐 DESIGNED — See `Progression.md` for full detail.
> **Impl files:** `DataService.lua` (persistence), `PlayerData.lua` (type), `StateService.lua` (runtime state)
> **Spec gaps:** No baseline Resonance Shard numbers, no soft-cap threshold values, no loss-on-death formula.

### RESONANCE — THE CORE GROWTH SYSTEM

Resonance is your character’s attunement to Vael’s remaining power. It’s gained through combat, exploration, crafting, and surviving. It gates ability upgrades, weapon mastery thresholds, and Ring access. Losing Resonance Shards on death is the primary punishment — it slows your progression temporarily without reversing it.

Resonance has a **soft cap per Ring** — you can only grow so far while remaining in Ring One. Advancing into darker rings isn’t just brave, it’s mechanically necessary to reach the next tier of your build. This creates natural pressure to push forward rather than grind in safety forever.

### THE THREE PILLARS

#### Aspect 🚫 FUTURE (most branches)

> **Impl files:** `AbilitySystem.lua`, `AbilityRegistry.lua`, `abilities/*.lua`
> **Spec gaps:** Cross-Aspect synergy bonuses have no numeric values. Communion branch abilities are design-only.

Your elemental-spiritual identity. Available Aspects at launch: Ash, Tide, Ember, Gale, Void, and Marrow (unlocks in Second Dimming). Each Aspect has three branches — **Expression** (offensive abilities), **Form** (passive combat modifications), and **Communion** (utility and exploration abilities). You can invest freely across branches but specialization is rewarded. A deep Expression build hits harder. A Communion-focused build has significant traversal and information advantages.

Aspects also have **Resonance with each other** — certain combinations create passive bonuses. Ash and Void together produce a concealment synergy. Tide and Gale create storm effects. These aren’t mandatory but they reward build experimentation and create genuinely distinctive character identities.

#### Discipline 📐 DESIGNED

> **Impl files:** `PlayerData.lua` (discipline field), `WeaponService.lua` (proficiency checks)
> **Spec gaps:** No numeric stat differences between disciplines. Cross-training Resonance cost has no baseline number.

Governs physical capability and weapon mastery. There are four Disciplines:

- **Wayward** — balanced, adaptable, good for newcomers
- **Ironclad** — heavy weapons, armor proficiency, high Poise scaling
- **Silhouette** — light weapons, mobility, Breath efficiency
- **Resonant** — low physical investment, high Aspect scaling, esoteric weapons like instruments and focuses

You choose one at character creation but can cross-train into secondary disciplines at significant Resonance cost — versatility is possible but expensive.

#### Omen 🚫 FUTURE

> **Impl files:** `PlayerData.lua` (omenMarks field — add if missing), `StateSyncService.lua` (broadcast visual state)
> **Spec gaps:** Cleansing cost curve not specified. Per-death Mark accumulation formula not specified.

The dark variable. Accumulated through dying, deep-zone exploration, specific Ashen Choir interactions, and certain Aspect overuse. Omen builds in Marks across five thresholds. At each threshold you gain access to a passive corruption ability but also a deepening visual transformation and a new way that enemies perceive you. High Omen players are both feared and hunted — the Ashen Choir reveres them, certain NPCs refuse to interact with them, and in PvP they broadcast subtle tells that experienced players learn to read. A full Omen character is one of the most powerful and most visible things in the game. Playing that path is a commitment.

### WEAPONS AND CRAFTING

> **Status:** 🔧 PARTIAL — Weapon registry and basic equip/attack loop exist.
> **Impl files:** `WeaponService.lua`, `WeaponController.lua`, `WeaponRegistry.lua`, `WeaponTypes.lua`, `weapons/*.lua`
> **Spec gaps:**
>   - Five weight classes exist in design but are **unnamed** — need names + stat tables.
>   - Resonance Groove depth thresholds (Whisper/Resonant/Soulbind) have no use-count targets.
>   - Crafting system is entirely unimplemented.

Weapons exist in five weight classes affecting Discipline requirements and Stamina interaction. Each weapon has a **Resonance Groove** — a passive slot that deepens as you use the weapon, eventually accepting one of three Aspect-infused modifications unique to that weapon type. A sword’s Groove might offer a parry extension, a counter-aura, or a ranged Aspect pulse. Finding the right Groove for your build is a significant mid-game investment.

Crafting uses materials gathered across Rings — darker Ring materials are dramatically better but require surviving long enough to collect them. There’s no auction house. Trading is player-to-player and entirely social, which means economy is community-driven and geography matters. Materials from Ring Three are genuinely rare on the market because getting them out is dangerous.

-----

## MOVEMENT

> **Status:** 🔧 PARTIAL — Sprint, dash, lunge exist. Wall-run, ledge catch, vault, slide are unimplemented.
> **Impl files:** `MovementController.lua`, `MovementConfig.lua`
> **Spec gaps (❓ UNSPECCED):**
>   - Breath drain rates per action (sprint / dash / wall-run) — no numbers
>   - Momentum multiplier ramp function — capped at 3× but ramp curve undefined
>   - Aspect movement modifiers — designed, not implemented

The base movement kit: sprint, dash (directional, with brief recovery), wall-run (2–3 steps maximum, momentum-dependent), ledge catch, vault, and slide. These chain together fluidly — a sprint into a vault into a wall-run into a directional dash is a single committed movement sequence that a skilled player can execute instinctively.

**Breath** governs movement actions. Sprinting, dashing, and wall-running all drain Breath. Breath recharges fastest when grounded. Running out of Breath mid-sequence causes a stumble animation — punishing overcommitment without being unforgiving about it.

**Momentum** is the hidden depth of the movement system. Maintaining speed through chained actions builds a momentum multiplier capped at 3x. High momentum increases the distance on dashes and the height on jumps, and gives melee strikes a slight damage bonus if you connect while running toward a target. Skilled movement isn’t just about getting places quickly — it’s a combat tool.

Each Aspect subtly modifies movement identity without creating unfair advantages:

- **Ash** — leaves false afterimage trails on dashes
- **Tide** — slides further, momentum preserved on wet terrain
- **Gale** — one mid-air directional redirect per jump
- **Ember** — slightly faster sprint acceleration
- **Void** — briefly phase through geometry corners on a cooldown
- **Marrow** — regenerates Poise faster during movement

**Environmental movement** matters significantly. The world is built with traversal in mind — there’s almost always a vertical path, a shortcut through ruins, a momentum line if you know the geography. Learning a region’s movement language is as rewarding as learning its combat encounters.

-----

## COMBAT — PVP

> **Status:** 🔧 PARTIAL
> **Impl files:** `CombatService.lua`, `ActionController.lua`, `PostureService.lua`, `DefenseService.lua`, `HitboxService.lua`, `WeaponEffectsController.lua`, `CombatFeedbackUI.lua`
> **What exists:** Attack pipeline, hitbox detection, posture system skeleton, basic defense.
> **Spec gaps:**
>   - Clash System — designed, not implemented. No frame-perfect detection logic specced.
>   - Condemned Mechanic — 📐 DESIGNED, not implemented
>   - Living Resonance Streak — 📐 DESIGNED, not implemented
>   - Dueling Grounds — 🚫 FUTURE
>   - Faction PvP flagging — 🚫 FUTURE
>   - Last Rites — 📐 DESIGNED, not implemented

### THE CORE LOOP

Combat centers on **Posture and HP** as two distinct health states. Posture is your structural integrity in a fight — it depletes when you block hits, take unguarded strikes, or absorb Aspect abilities. HP depletes from unblocked strikes and Break attacks. Letting your Posture fall to zero staggers you briefly, opening you for a **Break** — a deliberate, powerful strike that deals heavy HP damage and has a distinct visual and audio signature that other players nearby can hear.

The **Clash System** triggers when two attacks connect within the same frame. A brief Clash moment fires, both players push apart, and there’s a half-second window for a follow-up input — parry extension, counter-strike, or dash cancel. Successfully executing the follow-up deals bonus Posture damage and briefly staggers the opponent. Missing leaves you open. Clash moments are the game’s most dramatic beat and skilled players will start playing *toward* them intentionally.

**Aspect abilities** are aimed, timed, and often chargeable. There’s no auto-aim. A missed Ember burst in a fight is a genuine mistake with real consequences. Aspect abilities generally affect Posture more than HP, which means they’re used to create Break windows rather than deal direct damage — with exceptions in deep builds.

### PVP SYSTEMS

**The Condemned Mechanic** — if three or more players engage a solo target, that target gains the Condemned status: passive Posture recovery boost, slight damage reduction, and improved tracking on melee attacks. It doesn’t make you invincible against groups but it respects the solo player enough that skilled ones can survive and escape. Nightbound doesn’t reward zerging.

**The Living Resonance Streak** — the longer you survive without dying, the more a passive warm glow builds around your character. High-streak players are visible, respected, and targeted. Killing someone with a long streak rewards bonus Resonance Shards. Protecting your streak becomes a secondary objective in every encounter.

**Dueling Grounds** — instanced arenas accessible from The Hearthspire and faction outposts. 1v1 and 2v2 formats, no loss penalty, purely for practice and building **Repute**. Repute is a visible stat on player inspection. High Repute players have a subtle aura visible in the open world — a warning sign and a status symbol simultaneously.

**Faction PvP** — aligning with factions flags you in specific ways. Rival faction members are permanently marked to you in the open world beyond Ring One. This isn’t forced PvP — you can still choose your engagements — but the world has a political texture. Taking a Drift Gate controlled by a rival faction might mean running a gauntlet. Switching factions has a visible, social cost.

**Last Rites** — when you know death is coming, a brief active input lets you choose what you leave behind. Burn Resonance Shards to grant your killer bonus experience, or channel your Luminance into the ground to leave a permanent memorial brightening that spot and marking it with your name. Death becomes an authorial act.

-----

## COMBAT — PVE

> **Status:** 🔧 PARTIAL — Dummy NPCs exist for dev testing only. Actual enemy AI is unimplemented.
> **Impl files:** `DummyService.lua`, `DummyController.lua`, `DummyData.lua` (dev scaffolding)
> **Spec gaps:**
>   - Witnessing system — ❓ UNSPECCED mechanic (range? duration? Codex data structure?)
>   - All enemy AI behavior — Hollowed, Duskwalkers, Threadweavers, Ashen Choir, Preserved, Vaelborn — 🚫 FUTURE
>   - Boss encounter system — 🚫 FUTURE
>   - Convergence / World Boss events — 🚫 FUTURE

### ENEMY DESIGN PHILOSOPHY

Every enemy in Vael has a readable identity. They telegraph. They have patterns. But those patterns are deep enough that they reward sustained engagement rather than immediate aggression. The **Witnessing** system rewards observing enemies before attacking — the longer you watch without engaging, the more your character learns, unlocking Codex entries and occasionally revealing a combat hint specific to that creature.

### ENEMY ROSTER

**The Hollowed** — former Drifters and NPCs whose Luminance hit zero. They’re echoes, running through the motions of their last moments. They have recognizable movesets, near-player-level ability usage, and occasionally carry equipment. Fighting a Hollowed feels deeply uncanny. Some Hollowed are clearly repeating a fight they lost. Some are running from something that no longer exists.

**The Duskwalkers** — massive territorial creatures at Ring border zones. They don’t try to kill you — they herd you toward darkness. They block paths, destroy light sources, create shadow zones, and use Aspect-adjacent abilities to manipulate your movement options. Fighting one head-on is possible but punishing. Learning their herding logic and using it against them is how you actually beat them efficiently.

**Threadweavers** — deep-dark horror. They arrive at locations before players do and build trap infrastructure. You enter their area already at a disadvantage. Getting caught in a thread doesn’t deal immediate damage — it roots you and drains Luminance. Fighting a Threadweaver is as much about navigating and dismantling its environment as dealing damage. Solo attempts are brutal. A coordinated two-player run where one distracts while one dismantles is deeply satisfying.

**The Ashen Choir** — humanoid cultist faction who believe the dying sun is mercy. They fight in coordinated groups with genuine morale — kill the leader first and weaker members flee, kill weaker members first and the leader becomes aggressive and empowered. They use Aspect abilities. They communicate during fights, sometimes in ways that give away their next move if you’re listening. They are the most human enemies in the game and deliberately so.

**The Preserved** — found in Ring Three’s ruins. Formerly human, now architectural. They don’t move until disturbed. When they do move, it’s wrong — too fast, too still between bursts of motion. They use the environment as part of their attack pattern, leveraging the ruins around them. One of the game’s most unnerving enemy types.

**The Vaelborn** — Ring Four creatures that appear to have emerged from the twilight itself. They have no clear biology. They react to Luminance like prey reacting to predators — high-Luminance players draw their attention from further away. They are genuinely alien in behavior, attacking in ways that take time to parse. The Witnessing system is most valuable here.

### BOSSES

Bosses are not level-gated in the traditional sense — they’re **story-gated**. You encounter them by following threads rather than hitting a level requirement. Most bosses have a pre-encounter phase that can be skipped but rewards those who engage — talking to an NPC, finding a specific item, or Witnessing the boss in a non-combat context first modifies the fight in meaningful ways. The boss might acknowledge you. Might be slightly afraid. Might be more aggressive because you’ve learned too much.

Every boss has a **second form** that triggers at around 40% HP — not a health refill, but a behavioral shift. The arena changes. New mechanics activate. Players who’ve never seen the second form before experience genuine surprise, which is protected by the game’s lack of formal strategy documentation from Nightbound’s own developers.

### WORLD BOSSES — CONVERGENCE EVENTS

The server’s collective Luminance level is tracked. If the playerbase is struggling — too many deaths, too much time in deep zones, too many Hollowed emerging — a **Convergence** event triggers. A massive entity surfaces and begins moving toward Ring One, threatening The Hearthspire. Every player on the server is notified through environmental tells before any UI prompt. The sky changes. NPCs panic. The Duskwalkers flee inward.

Defeating a Convergence entity requires coordination between PvP and PvE players who might otherwise be antagonistic. It drops the game’s best materials and restores server Luminance. Failing one — which is possible — has lasting consequences for that server.

-----

## DEATH & THE INCENTIVE TO SURVIVE

> **Status:** 📐 DESIGNED — None of this is implemented yet.
> **Impl files (target):** `DataService.lua` (Shard loss), `PlayerData.lua` (streak/Dimming debuff fields), `NetworkService.lua` (revive event)
> **Spec gaps:**
>   - The Between: revival initiation UX — how does a nearby player see/trigger the revive? Range? Prompt?
>   - Ember Points: how many per player? Persistent across sessions (DataStore) or session-only?
>   - Dimming debuff: duration not specified ("short real-time window" is not a number)
>   - Resonance Shard loss on death: no formula (flat amount? % of in-flight Shards? scaled by Ring?)

### THE BETWEEN

When you die, you enter a brief state called **The Between** — a liminal, desaturated version of wherever you fell. You can see the world around your corpse, faintly, like looking through fogged glass. You have roughly 30 seconds here. Other players can see a faint marker where you fell and can choose to *revive* you at the cost of some of their own Luminance — a genuine act of sacrifice that builds real social bonds. If nobody does, or the timer runs out, you respawn at your last **Ember Point**.

### WHAT YOU LOSE

What you lose on death is calibrated carefully. You drop Resonance Shards, some consumables, and take a temporary **Dimming** debuff — your Luminance cap is reduced for a short real-time window. This means you’re slightly more vulnerable and restricted immediately after dying, which creates pressure without cruelty. You never lose your Aspect, your Discipline investment, your weapons, or your Omen progress.

### THE STREAK

The incentive to stay alive comes from **The Streak** — the longer you survive without dying, the more a passive bonus called **Living Resonance** accumulates. It manifests as a faint warm glow around your character that other players can see, and mechanically it accelerates your shard gain, slightly boosts crafting quality, and improves your chances at rare drops from enemies. Veterans walking around with a deep Living Resonance glow are immediately recognizable as people who’ve been surviving for a long time. It’s a status symbol tied directly to staying alive.

### LAST RITES

If you know you’re about to die, you can trigger a brief active input that lets you *choose* what you leave behind. You can burn some of your Resonance Shards to boost the experience of whoever kills you, or you can channel your remaining Luminance into the ground, permanently brightening a small area of the world slightly and leaving a visible memorial mark with your name on it. Neither is mandatory, but both make death feel like it meant something.

-----

## META PROGRESSION — THE ASHEN RECORD

> **Status:** 📐 DESIGNED — Not implemented.
> **Impl files (target):** `DataService.lua` (account-scope DataStore key separate from character key)
> **Spec gaps:**
>   - Ashen Record DataStore schema not defined
>   - Echo unlock list is illustrative only — no complete table of all Echoes
>   - Umbral Codex data format unspecced (entries, categories, unlock conditions)
>   - Cosmetics system unimplemented; no asset pipeline defined

The Ashen Record is your account-level history — it persists completely across deaths and even character resets. It tracks everything: enemies you’ve witnessed and catalogued, bosses you’ve defeated, factions you’ve aligned with, regions you’ve explored, players you’ve dueled, and your total survival time across all runs. This record is visible to other players when they inspect you and functions as your real identity in the world.

### ECHOES

Mechanically, the Ashen Record grants **Echoes** — passive, minor unlocks that carry into new characters. These are deliberately kept small. Things like starting with slightly more Breath, unlocking a second Ember Point slot earlier, having one additional Aspect option available during character creation, or getting a marginal Luminance bonus in regions you’ve previously explored. Echoes don’t make new characters powerful — they make them *slightly more informed*.

### COSMETICS

Deaths, streaks, boss kills, and exploration milestones unlock visual items — character markings, weapon trails, Drift Gate animations, memorial stone designs — that persist forever and can never be lost. These are entirely non-combat and non-stat affecting, purely expressive, but they’re the most visible sign of a player’s history in the world.

### THE UMBRAL CODEX

A meta-account book of lore, creature entries, faction histories, and world fragments you’ve collected across all your characters. It fills in over time and is purely narrative reward. It exists for the players who want to understand the world deeply and gives longtime players something genuinely exclusive — not power, but knowledge and context that newer players haven’t earned yet.

The philosophy is: **your character is temporary and mortal, but you as a player are accumulating something real.**

-----

## THE WORLD — GEOGRAPHY AND SYSTEMS

> **Status:** 📐 DESIGNED — World zones are narrative design only; no Ring transition or Luminance drain system exists yet.
> **Spec gaps:**
>   - Drift Gate mechanic: activation UX, cooldown, return travel — unspecced
>   - Dimming Cycles: duration, cadence, server-side scheduling — unspecced
>   - Server-wide Luminance tracking: data structure and sync mechanism — ❓ UNSPECCED

### RINGS AT A GLANCE

|Ring|Name             |Tone                       |Luminance Drain|
|----|-----------------|---------------------------|---------------|
|0   |The Hearthspire  |Safe city, social hub      |None           |
|1   |The Verdant Shelf|Forests, grounded danger   |None           |
|2   |The Ashfeld      |Dead lands, Choir territory|Minimal        |
|3   |The Vael Depths  |Ancient ruins, deep lore   |Moderate       |
|4   |The Gloam        |True dark, no compass      |Active drain   |
|5   |The Null         |Endgame, mystery resolved  |Constant drain |

### DRIFT GATES

There are no mounts. Travel across rings is done through **Drift Gates** — ancient structures that still function, maintained by NPC factions. Fast travel exists but is gated behind faction standing, meaning early on you’re walking the world and learning it intimately. Later, you’re choosing which factions to align with, which determines which gates you can use — and those same factions have different attitudes toward PvP, meaning your allegiance flags you to other players in subtle ways.

### DIMMING CYCLES

Seasons in the game are replaced by **Dimming Cycles** — periodic events where the world gets measurably darker for several in-game days. During a Dimming Cycle, enemy behavior changes, new creatures emerge, and certain items and crafting materials only exist in this window. It creates a natural rhythm of tension and release for the entire playerbase.

-----

## FACTIONS

> **Status:** 🚫 FUTURE — Faction system is entirely unimplemented.
> **Impl files (target):** `DataService.lua` (factionId field on PlayerData), new `FactionService.lua`
> **Spec gaps:**
>   - NPC quest system: no mechanic designed (branching, completion hooks, reward delivery)
>   - Faction switching: described as having "visible social cost" — no mechanical penalty defined
>   - Faction-gated Drift Gate access: no gate ownership data structure defined
>   - Unmarked "Unbound" stat bonus: described qualitatively only, no numbers

Factions are not simple good/evil splits. Each one has a coherent worldview that makes internal sense, and aligning with one is a statement about what kind of Drifter you are.

**The Pillar Wardens** — devoted protectors of The Hearthspire and the Solstice Pillars. They believe survival means holding the line. Conservative, militaristic, and suspicious of Omen-marked Drifters. They control the most Drift Gates and offer the best armor crafting access. Aligning with them marks you as a protector — NPCs trust you more, certain enemies de-aggro, but the Ashen Choir actively hunts you.

**The Wandering Court** — a loose confederation of traders, explorers, and information brokers who’ve decided the only way to understand the twilight is to walk toward it. Neutral on PvP, valuable for lore, and the only faction that maintains diplomatic contact with the Ashen Choir. They control the best market networks and offer unique movement-enhancing items. Aligning with them gives you access to Memory Fragments before other factions can reach them.

**The Ashen Choir** — believers that the dying sun is mercy. Not mindlessly evil — they have philosophy, hierarchy, and genuine community. They welcome Omen-marked Drifters warmly. They control Ring Two territory significantly and offer Omen-accelerating items and exclusive Marrow Aspect knowledge. Aligning with them marks you visually and other faction members treat you with open hostility. The most difficult and rewarding faction path.

**The Unmarked** — players who refuse to align with any faction. They lose access to faction-specific crafting and gates but gain the unique passive **Unbound** — slightly better stats in all areas at the cost of the social infrastructure that factions provide. Playing Unmarked is a statement. Other players read it as either principled or dangerous.

-----

> *“The sun didn’t die. It’s still there — somewhere behind all of this. You can feel it if you stand very still in the Verdant Shelf at the right moment and close your eyes. Something warm. Something that remembers you. Keep moving toward it. Even if moving toward it means going the wrong direction for a very long time.”*
>
> — Found written on a wall in the Vael Depths, author unknown