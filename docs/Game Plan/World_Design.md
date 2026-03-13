# Nightbound World Design — The Four Rings

**Document Version:** 1.0  
**Last Updated:** March 13, 2026  
**Related Issue:** [#178](https://github.com/JoshuaKushnir/Nightfall/issues/178)

---

## Story Context

Vael is a continent trapped in twilight. The last light comes from the **Solstice Pillar**, a structure at the heart of **Hearthspire**. Rings radiate outward from the city, each progressively darker and more dangerous. The player is a **Drifter**: a twilight-marked being who dies and returns, growing stronger each cycle, feared as an omen.

The visual logic of the world is singular: **the further you go, the less the world is trying to be reassuring.**

---

## Design Principles

- **3-Enemy Types Per Zone**: Each zone has exactly 3 distinct enemy archetypes, each teaching a specific mechanic or counter-strategy
- **1 Miniboss Per Zone**: Serves as a zone's capstone encounter and lore anchor
- **Progression Clarity**: Enemy complexity and threat increases Ring-by-Ring
- **Witnessing System**: Observing enemies before combat grants tactical knowledge (visible to players in Codex)
- **Environmental Storytelling**: Zone layout and NPC presence tell story without exposition

---

## The Sky

The first thing you notice is that the sky is wrong. It's not night. It's not day. It's the colour of a bruised amber — deep gold bleeding into grey at the edges, like someone pressed pause on a sunset three hundred years ago and walked away. There are no stars visible, but there's no sun either. The light has no point of origin. It just is, diffused and directionless, casting shadows that don't quite line up with where they should fall.

Clouds exist but move slowly. When they catch the ambiguous light they turn colours that clouds shouldn't be — deep orange, pale violet, ash white. The horizon always looks like it's on fire somewhere just out of sight. It never is.

---

# Ring 0 — Hearthspire

**The Safe City. The Last Light. The Reference Point.**

The Solstice Pillar is the first thing visible from anywhere in Ring 1 and most of Ring 2. It rises from the city's centre — not a tower, more like a shard of something that was already here when people arrived and built around it. White stone that isn't quite stone, smooth in a way that suggests it was never carved, tall enough that its peak disappears into the amber haze above. It pulses. Not rhythmically — irregularly, like a heartbeat after a long run. The pulse is warm gold, and it's the only genuinely warm light in the entire world.

The city is built into and around a plateau. Not a dramatic cliff — a gradual rise over several hundred metres that gives Hearthspire a natural defensive position and, more importantly, puts it slightly closer to whatever the light source is. The streets are narrow and vertical — lots of stairs, ramps, bridges between districts built at different elevations. The architecture is dense stone, old, layered over itself across generations. Lower districts are louder, warmer, more transactional. Upper districts near the Pillar are quieter, more formal, lit more strongly by the pulse.

The city's edge isn't a wall exactly. It's where the buildings stop and the Pillar's light begins losing the fight against the ambient grey. You can see the moment you're about to leave Ring 0 — the colour temperature shifts, the shadows deepen slightly, and the ground changes from paved stone to the beginning of something else.

---

# Ring 1 — The Verdant Shelf

**Entry zone. Diseased beauty. First death.**

The "shelf" is literal. Ring 1 sits on a wide natural plateau that drops away at its outer edge into the lowlands of Ring 2. The elevation change is significant — maybe 40 or 50 metres of cliff face running in a ragged arc around the far side of Ring 1, with a few natural breaks where Drift Gates have been built. Standing at that cliff edge and looking outward into Ring 2 is one of the game's first genuinely unsettling moments.

But inward, Ring 1 is almost beautiful in the way something diseased can still be structurally beautiful.

The forests are dense. The trees are large-trunked, old growth, and every single one leans slightly toward Hearthspire. Not dramatically — maybe ten or fifteen degrees — but enough that once you notice it you can't stop noticing it. Walking through the forest feels like being watched by something that's very slowly turning to look at you. The canopy is thick enough to create pools of deeper shadow between the diffuse sky-light and the forest floor. The undergrowth is wrong: plants grow in spirals toward the Pillar's direction, flowers bloom facing inward regardless of where the light falls, roots surface on the outward-facing sides of trees as if the trees are trying to pull themselves away from the outer dark.

The Drowned Meadow sits in a natural depression in the shelf — a shallow bowl that collects water. The water is dark. Not murky from sediment, just dark, like it's slightly deeper than physics would explain. The meadow grass around it is pale, almost white, and grows perfectly flat in concentric rings around the water. Standing at the edge of the meadow and looking across it feels like looking at something that's looking back.

The Ashward Fringe is where the shelf's soil starts changing. The grass thins, then stops. The ground becomes greyer, drier, more compacted. The trees at this edge are still leaning toward Hearthspire but they're dead — bleached trunks, no bark, branches that reach inward like outstretched arms. The cliff drop to Ring 2 starts here, and the view down into the Ashfeld below is the first time the game shows you clearly how far you're going to have to travel.

## Zone 1A — The Canopy Road

**The entry corridor. Twisted forest, trees leaning toward Hearthspire. Light still reaches here.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Hollowed Drifter** | Melee stalker | Repeats a combat loop from their past life. Predictable rhythm, dangerous if you don't learn it. Witnessing reveals which loop they're stuck in. |
| **Hollowed Sentinel** | Heavy / Tank | Former Ironclad. Posture-forward. Won't chase — holds ground and punishes aggression. Breaking its posture is the entire puzzle. |
| **Greyback** | Creature | A boar-sized animal, wrong in the way Ring 1 animals are wrong — grey-furred, growing toward Hearthspire light, attacking anything that moves between it and the glow. Fast, low HP, hits hard on a charge. Teaches dodging before enemy movesets get complex. |

### Miniboss — The Hollow Keeper

A Hollowed NPC who was a Pillar Warden. Still wearing the armor. Still running a patrol route — but it's the patrol route of a Hearthspire they remember that no longer exists, so they walk through walls and out of bounds before snapping back.

**Two phases:**
- **Phase 1**: Methodical Warden patterns
- **Phase 2**: The loop breaks and they become erratic and desperate

*Witnessing them before the fight shows the patrol — which tells you Phase 2's behavior in advance.*

---

## Zone 1B — The Drowned Meadow

**A low-lying plain that floods with dark, cold water during Dimming Cycles. Tide players have movement advantages here.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Hollowed Fisher** | Ranged harasser | Throws weighted hooks that root on contact for 1s. Low HP. Meant to be closed on quickly or dealt with at range. Teaches players to manage distance and punishes passive fighting. |
| **Murk Lurker** | Ambush creature | Submerges in shallow water, invisible until you step within 4 studs. Erupts upward and deals a heavy Posture hit. Witnessing reveals their position before they submerge. |
| **Saturated Hollowed** | Status spreader | A Hollowed soaked through from time in the water. Every attack applies Saturated status to the player, amplifying Tide-type damage. Dangerous in groups — alone it's manageable. |

### Miniboss — The Tidecaller Echo

A Hollowed who was once a Tide Aspect user. Now they're locked in a loop of an ability they could never quite execute before they hollowed. The fight involves a half-cast Tide ability going off unpredictably — water surges, slippery terrain, knockback. They cannot be still. They're constantly moving, which means a patient player can read their loop and punish the recovery.

*A Silhouette or Wayward player can chase them effectively; an Ironclad player must learn to bait instead.*

---

## Zone 1C — The Ashward Fringe

**The far edge of Ring 1, where the forest gives way to the first grey soil of Ring 2. Duskwalkers patrol the border.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Hollowed Scout** | Fast skirmisher | Former Silhouette. Feints constantly. If you block more than twice in a row it will bypass your guard entirely on the third hit. Teaches players not to rely on block as a crutch. |
| **Fringe Creeper** | Territorial creature | Crab-like, moves sideways, attacks from outside normal camera angles. Not hard but deliberately disorienting. Its Codex entry has a note: "Evolved to approach from where you're not looking." |
| **Dimling** | Environmental hazard-creature | Tiny, harmless alone. Spawns in clusters during low-Luminance conditions. Each one drains a tiny amount of Luminance on contact. A swarm of 8-10 will drain Luminance fast enough to matter. Can be scattered with any AoE or a heavy stomp. |

### Miniboss — The Duskwalker Warden (Ring Exit Gate)

Not a Hollowed. The first real Duskwalker encounter. **Cannot be killed at Ring 1 progression** — it's survivable, not killable. It herds you. The "fight" is navigating its herding logic to reach the Drift Gate while it blocks and redirects you.

*Players who Witnessed it know which directions it won't push toward. Players who charged it directly learn quickly why that's wrong.*

**Rewards:** Codex entry, Resonance bonus, Ring 2 gate unlocked.

---

# Ring 2 — The Ashfeld

**Dead civilization. Omen pressure begins. The Ashen Choir's hunting ground.**

The drop from Ring 1's plateau shelf into Ring 2 changes everything. The amber haze above is darker here — more grey than gold. The light that reaches the ground is thinner, cooler, directional in the way Ring 1's wasn't. Shadows are longer and sharper.

The Ashfeld is flat. Not gentle rolling plains flat — deliberately flat, the flatness of a place where everything that created elevation was slowly ground down. Former riverbeds cut through it as dry trenches, anywhere from two to fifteen metres deep, with cracked clay walls. These trenches are the primary navigation feature of Ring 2. They create natural corridors, natural ambush points, natural shelter from the wind that moves constantly across the open ground.

The roads are still there. Wide paved roads, built for carts and foot traffic, running between the foundations of former settlements. The settlements themselves are present as geometry — foundation outlines, the lower courses of stone walls, hearth locations identifiable by the shape of remaining chimneys standing alone without buildings. Everything above about two metres has been removed by time and weight and the slow collapse of whatever held things together. The infrastructure of a civilization that stopped, preserved in outline.

The dead forests of the Ashfeld are different from Ring 1's living ones. The trees didn't fall — they dried in place. They're still standing, still densely packed in former groves, but their bark is ash-grey and their branches are bare and they make a sound in the wind that's somewhere between wood and bone. Walking through them at distance looks like walking through a crowd of people who've stopped.

The Choir Outpost breaks this flatness deliberately. They've built upward — towers made from salvaged stone from the ruins, elevated walkways, a structure that dominates the surrounding flatland by maybe twenty metres. It's visible from a long way off. It's meant to be. The Choir doesn't hide.

## Zone 2A — The Ashroads

**Cracked paved roads, foundations of buildings, the skeleton of a functioning society. Ashen Choir scouts operate here.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Choir Initiate** | Humanoid / Aggressive | Weakest Choir unit. Fights alone poorly but has a distress signal — if not killed within ~8 seconds of aggroing, calls nearby Choir. Teaches players to commit to engagements fast. |
| **Choir Penitent** | Humanoid / Support | Doesn't fight directly. Stays back and empowers nearby Choir with a chant. Killing them first breaks group morale; killing them last is a waste since the Choir collapses when its leader dies. Teaches target priority. |
| **Ash Hound** | Creature | Former domesticated animal. Runs in loose packs of 2-3, coordinating loosely. One feints, one flanks. Not smart — but they have a rhythm. Witnessing reveals the flanker always approaches from the left. |

### Miniboss — Choir Taskmaster

A mid-rank Choir commander who fights with genuine Aspect ability usage (Ash). Morale mechanic applies: any Choir nearby are empowered while she's alive. Killing her first triggers a route. But she's dangerous enough that players may be tempted to clear adds first — which empowers her further and is the "wrong" approach.

**Two phases:**
- **Phase 1**: Standard command posture
- **Phase 2**: She deliberately sacrifices Choir allies to fuel an ability, which is the tell that she's getting desperate

---

## Zone 2B — The Dried Basin

**A former riverbed. Tide Communion players can detect residual energy here. The ground is cracked, with elevation differences that affect combat significantly.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Hollowed Channeler** | Aspect-user echo | A Hollowed stuck mid-cast of an ability they never finished. Their attack pattern is built around an incomplete ability — it fires, misfires, or goes wrong in ways that are dangerous but readable. Adds lore: some Hollowed are people who died at a specific moment. |
| **Basin Stalker** | Creature | Large, slow ambush predator. Uses elevation — waits at cliff edges and drops on players below. High posture damage on land hit. Not hard to dodge once you know it's there. Witnessing teaches that it only drops when you stand still for 3 seconds. |
| **Petrified Hollowed** | Environmental / Undead | Stands completely still. Looks like a statue. Starts moving when you turn your back. If you face them, they freeze again. Requires constant awareness during exploration of the zone. Low HP once engaged directly. |

### Miniboss — The Basin Wraith

Not Hollowed, not Choir — something older that lives in the basin. Partially elemental, responds to Luminance. Players with high Luminance have a harder fight because it's drawn more aggressively. Players with lower Luminance (from Omen accumulation or natural drain) find it slightly less aggressive.

*First enemy in the game that actively discourages being lit up — subtle foreshadowing of Ring 4 mechanics.*

---

## Zone 2C — The Choir Outpost

**A functioning Ashen Choir settlement. Hostile to non-Choir players, but observably populated — this is their home, not their hunting ground.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Choir Vanguard** | Elite humanoid | Full Aspect ability access. Fights with genuine combination pressure — a setup into a Posture hit into a Break attempt. The first enemy in the game that plays like a player character. Teaches players what being on the receiving end of their own kit feels like. |
| **Choir Archivist** | Humanoid / Debuffer | Applies Silenced status via a thrown object. Doesn't fight in melee. Priority target; if left alone for 15 seconds, starts a ritual that buffs all nearby Choir with Dampened (affecting player Aspect abilities). |
| **Ashen Familiar** | Choir-bound creature | A small creature carried by Choir Archivists. Harmless alone. If the Archivist dies while it's alive, it enters a frenzied state and deals significant damage for 10 seconds before expiring. Punishes players who kill the pet first. |

### Miniboss — The Choir Adjudicant

The Outpost's senior Choir figure. Doesn't treat the player as an enemy initially — has dialogue. If the player is Choir-aligned, this becomes a different encounter (a challenge bout, not a fight-to-the-death). If not aligned, she engages properly.

**Two phases:**
- **Phase 1**: Formal, measured combat
- **Phase 2**: Uses a Marrow-adjacent ability, which is a lore reveal — the Choir are closer to Marrow knowledge than anyone else

---

# Ring 3 — Vael Depths

**Pre-twilight ruins. The world's history lives here. Vertical architecture. Old beyond measure.**

The transition into Ring 3 isn't an elevation change — it's a descent. Not a cliff, but a long downward slope where the ground simply keeps going down, following geological strata until you're in a kind of enormous natural bowl. The bowl's edges are the ruins of the old world's most ambitious architecture. The centre is lower, older, stranger.

The buildings here are intact in a way that feels wrong. Three-storey buildings with their facades still standing. Covered walkways still connected between structures. A civic plaza with its paving stones still level, still fitted together. Everything is coated in a fine grey film — not dust, something more uniform, like the air itself deposited a layer of itself onto every surface over centuries.

The light here is different. It comes from below as much as above. Something in the stone of the Depths fluoresces faintly — a cold blue-grey glow that comes from the walls themselves, from the floors, from the carved faces on the building fronts that were clearly important architectural elements and now look like they're softly illuminated from behind. It's enough to see by. It's not enough to feel safe in.

Vertical space is the defining feature of Ring 3. The collapsed architecture creates traversal opportunities that nowhere else has — floors giving way to floors below, structures leaning against each other at angles that create ramps, collapsed roofs creating bridges between buildings that were never meant to be connected. Players who learn Ring 3's vertical geography can move through encounter rooms that ground-level players can't bypass. The Preserved enemies know all the ground-level paths. They don't know the ceiling routes.

## Zone 3A — The Hall of Accord

**A massive civic building, preserved mid-meeting. Tables still set, chairs still occupied — by the Preserved.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **The Preserved (Seated)** | Environmental ambush | Doesn't move until disturbed. Witnessing reveals they react to sound, not sight — moving slowly past them is safe; attacking anything nearby triggers all of them. |
| **The Preserved (Standing)** | Patrol / Interceptor | Moves in fixed paths, doesn't deviate. Incredibly fast when in motion, completely still between bursts. The windows between their movement are the only safe combat windows. |
| **Memory Shade** | Lore-linked creature | Not hostile unless touched. Appears as a translucent echo of a former person, walking through their old routine. Contact deals no damage but applies a brief Slow status and triggers a Codex memory fragment. Rare. |

### Miniboss — The Last Accord-Keeper

A Preserved who was clearly mid-speech when the twilight froze everything. Still stands at the podium. The fight uses the Hall's architecture — columns, elevated platforms, the remnant of whatever they were discussing on a chalkboard.

**Two phases:**
- **Phase 1**: Formal, positioned movement using environment
- **Phase 2**: The Accord-Keeper loses their formal posture entirely and becomes something purely feral, which is deeply unsettling given how composed Phase 1 was

---

## Zone 3B — The Collapsed Archive

**A former library. Floors have given way, creating vertical combat space. Threadweavers have been here long enough to fully trap the structure.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Threadweaver (Lurker)** | Environmental builder | Installs threads between objects before combat begins. Entering the zone means navigating existing trap infrastructure before engaging. |
| **Threadweaver (Hunter)** | Active aggressor | Doesn't build — hunts. Throws threads in combat as ranged roots. More dangerous in an already-threaded environment because threads overlap. |
| **Archive Crawler** | Creature / Scavenger | A large insect-like creature that lives in the collapsed shelving. Non-hostile until you damage a Threadweaver, which they consider territory violation. Attacking players by dropping from above. |

### Miniboss — The Archivist-Weave

A Threadweaver that has been in this Archive so long it has partially merged with the structure. The fight involves navigating a room that is itself partially the enemy. Destroying threads weakens it. Destroying the right threads — the load-bearing ones — partially collapses sections of the arena, opening new paths and eliminating specific attack vectors.

*Most mechanically complex fight so far.*

---

## Zone 3C — The Memorial Quarter

**Where the old world buried its dead — and something is wrong with what's buried there.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Hollow Revenant** | Undead / Persistent | Can't be permanently killed in this zone — respawns at a memorial stone nearby unless the stone is destroyed first. Teaches players to address the source. |
| **The Grief-Touched** | Humanoid / Omen-linked | Former explorers driven to Omen Mark V by extended time in the Depths. Not quite Hollowed — still aware, still reactive, deeply hostile. Drops Choir-adjacent materials suggesting the Choir visits this zone. |
| **Warden Ghost** | Lore / Semi-hostile | A Luminance echo of a Pillar Warden from before the twilight. Attacks only if you have high Omen marks. Otherwise: passive, walks old patrol routes, occasionally stops and looks at where Hearthspire would be visible. |

### Miniboss — The First Drifter

The first person who ever returned after death in Vael. Has been in the Depths since before anyone alive remembers. Not hostile — sits at a memorial, has dialogue. But if provoked (or if you have Omen Mark IV+, in which case they perceive you as a threat), they fight.

*The most technically skilled miniboss in Ring 3 because they've had centuries to learn combat.*

**Witnessing them reveals they used to visit Hearthspire before something changed. The Codex entry is the most-discussed lore piece in the game.**

---

# Ring 4 — The Gloam

**Luminance drains. Compass markers disappear in PvP. The threshold between seen and unseen.**

The transition into Ring 4 isn't an elevation change — it's a weather change. There's a boundary, maybe twenty metres wide, where the ambient light simply stops winning. On one side: dim but present, the grey-gold of a world still technically lit. On the other: something that isn't quite darkness but is much closer to it than anything in the shallower rings. The boundary is marked by a persistent ground-level mist that starts at ankle height and rises to about mid-torso in the denser parts. The mist is slightly luminescent — a cold blue-white that provides just enough visibility to make the darkness feel like a choice rather than an absence.

The Gloam is hilly in a way the Ashfeld isn't. The terrain rolls unevenly, with sudden drops and unexpected rises that are difficult to predict without prior knowledge. The wind tunnels are natural formations — channels cut between hills by some pre-twilight geological process — and they're the primary fast-travel arteries for players who've learned them. Gale Aspect players treat them as highways. Everyone else treats them as shelter from the open exposed hilltops where the Vaelborn have sightlines.

The Sunken Choir Shrine is built into one of these hillsides, half underground. Its entrance is a carved archway descending into the hill, and the interior opens into a space much larger than the exterior suggests. The Choir built downward here, not upward. Their architecture gets increasingly subterranean the further into their territory you go. It's ambiguous whether this is theology or practicality.

From the highest points of the Gloam's hills, on what passes for a clear day, you can see the Null. It looks like a hole. Not a physical hole — there's land there, visible, but the light above it is simply absent. A circular region of the sky above the Null is genuinely dark, not twilight-dark but black, a column of absent light that extends up into the haze and doesn't stop. Looking at it for more than a few seconds makes something in your vision blur slightly, like your eyes can't agree on how to process what they're seeing.

## Zone 4A — The Windfield

**Open terrain, wind tunnels, Gale players move here fastest. Vaelborn hunt by Luminance.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Vaelborn Drifter** | Alien / Luminance-hunter | Attacks high-Luminance targets first. Players who manage their Luminance actively have an easier fight. First enemy that actively punishes being too healthy/bright. |
| **Vaelborn Pack** | Swarm / Coordination | 4-6 small Vaelborn that share a health pool with a designated anchor. Kill the anchor and the swarm collapses. Anchor is visually distinct but may not be the closest one. |
| **Gloam Shade** | Environmental | Not killable. Passes through the zone on a path. Players caught in its path are Slowed and Luminance-drained for 3 seconds. Avoidable with observation. |

### Miniboss — The Luminance Eater

A Vaelborn that has consumed enough Luminance to develop intelligence. Hunts cooperatively with other Vaelborn in its territory.

**Two phases:**
- **Phase 1**: Aggressive predatory hunting
- **Phase 2**: Begins generating a darkness field that suppresses Aspect abilities in a radius — first encounter with ability suppression at a boss level

---

## Zone 4B — The Sunken Choir Shrine

**A Choir religious site in the Gloam. They're not surprised to see you here. They expected you.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Choir Ascendant** | Elite / Omen-empowered | Choir member who deliberately accumulated Omen Marks. Their abilities are corrupted versions — stronger but erratic. The Omen system made visible as an enemy archetype. |
| **Shrine Warden** | Choir / Defensive | Guards the shrine's approach. Doesn't advance, doesn't pursue. Extremely dangerous to fight at the shrine's threshold due to positional advantages. Pulls back to a defensive formation if pressured. |
| **Hollowed Pilgrim** | Former visitor | A Drifter who came to the shrine and hollowed here. Runs the pilgrimage route on loop. Pathetic and dangerous in equal measure. |

### Miniboss — The Shrine's Chosen

A Choir Ascendant who has willingly reached Omen Mark V. Entirely corrupted. The fight is the consequence of the Omen system taken to its endpoint — you're fighting what happens when someone chooses to keep going past every warning.

**Two phases:**
- **Phase 1**: Furious ability casting
- **Phase 2**: The corruption becomes visible on the arena itself; the shrine's walls begin suppressing Luminance in the space

---

## Zone 4C — The Null Approach

**The threshold. The Null is visible. Nothing living here by accident.**

### Enemies

| Enemy | Type | Core Mechanic |
|-------|------|---------------|
| **Null-Touched Hollowed** | Advanced Hollowed | Hollowed that have drifted too close to the Null and been changed by it. Void-adjacent abilities. Faster, harder to read, their Codex entries are incomplete because nobody has Witnessed them long enough. |
| **The Wandering Preserved** | Animated ruin | A Preserved from Ring 3 that has migrated outward. Shouldn't be here. Its presence is a lore mystery. Fights identically to Ring 3 Preserved but with Null-amplified speed. |
| **Convergence Herald** | Pre-boss entity | Only appears when server Luminance drops below a threshold. Signals an incoming Convergence event. Cannot be killed — can only be survived. |

### Miniboss — The Null Sentinel

Something that doesn't want you to enter the Null.

**Two phases:**
- **Phase 1**: Warning — it pushes you back, applies roots and knockback, tries to herd you away
- **Phase 2**: Genuine hostility after you demonstrate you're going forward anyway

*The tone shift between phases is the whole emotional point. You earned your right to proceed by refusing to leave.*

---

# Ring 5 — The Null

**End-game zone. No structured content. This is not a raid dungeon.**

The ground in the Null is the only ground in Vael that's level by design rather than accident. It's flat and dark and the stone here has no fluorescence — it absorbs light rather than reflecting it. Hearthspire is still visible from the Null, far in the distance, the Pillar's pulse a barely perceptible flicker at the horizon. It's the only reference point.

The sky column above is the inverse of the Pillar — where the Pillar emits, this absorbs. Whatever is happening at the centre of the Null is the answer to every question the world has been asking since the twilight started. The architecture here, if it can be called that, is not built. It grew. Or it was always here, and everything else grew around it.

The Null doesn't look like an endgame zone. It looks like the place where something very old is sleeping, and you are deciding whether to wake it.

Ring 5 is the **Convergence event** itself — a different design category entirely from structured zone encounters. See Phase 5 documentation for details.

---

# Enemy Roster Summary

## By Ring

| Ring | Zones | Total Enemy Types | Total Minibosses | Progression Focus |
|------|-------|-------------------|------------------|-------------------|
| **Ring 1** | Canopy Road, Drowned Meadow, Ashward Fringe | 9 (Hollowed, Creatures) | 3 | Learning loops, dodging, positioning |
| **Ring 2** | Ashroads, Dried Basin, Choir Outpost | 9 (Hollowed, Creatures, Choir) | 3 | Target priority, status effects, group tactics |
| **Ring 3** | Hall of Accord, Collapsed Archive, Memorial Quarter | 9 (Preserved, Threadweavers, Echoes) | 3 | Environmental use, verticality, lore engagement |
| **Ring 4** | Windfield, Sunken Choir Shrine, Null Approach | 9 (Vaelborn, Choir, Elites) | 3 | Ability suppression, Luminance awareness, desperation |
| **Ring 5** | The Null | Convergence Event | Convergence | Server-wide, permanent consequences |

## Enemy Archetypes

| Archetype | First Ring | Progression | Characteristic |
|-----------|-----------|-------------|-----------------|
| **Hollowed** | Ring 1 | Predictable loops | Lore-driven, readable patterns |
| **Creatures** | Ring 1 | Environmental hazards | Fast, high impact, low HP |
| **Duskwalkers** | Ring 1 Exit | Unkillable gates | Herding mechanics, area denial |
| **Ashen Choir** | Ring 2 | Humanoid tactics | Ability users, group coordination |
| **Preserved** | Ring 3 | Temporal echoes | Still / fast timing, environmental anchors |
| **Threadweavers** | Ring 3 | Trap builders | Environmental modifiers, arena design |
| **Vaelborn** | Ring 4 | Alien intelligences | Luminance-sensing, ability suppression |
| **Elite Choir** | Ring 4 | Corrupted ascendants | Omen Mark visual, player-like tactics |

---

# Implementation Roadmap

## Phase 4a: World Structure
- [ ] Zone geometry and landmarks created in Studio
- [ ] Enemy entity baseplates positioned
- [ ] Navigation pathways marked

## Phase 4b: Enemy AI Foundation
- [ ] HitboxService refinements for enemy-vs-player detection (Issue #175)
- [ ] Basic aggro radius and patrol patterns
- [ ] StateService extensions for NPC state machines

## Phase 4c: NPC Dialogue & Witnessing
- [ ] DialogueService implementation (Issue #177)
- [ ] Witnessing system interaction with Codex
- [ ] Story-gating for zone progression

## Phase 4d: Zone Triggers & Area Effects
- [ ] Zone ring transitions and HUD updates (Issue #176)
- [ ] Luminance drain in Ring 4
- [ ] Environmental hazards (Gloam Shade, wind tunnels, etc.)

---

# Spec Gaps & Placeholders

- **Enemy HP/Posture values**: To be tuned during playtesting
- **Ability damage/cooldowns for Choir/Vaelborn**: Pending magic system completion
- **Miniboss phase 2 thresholds**: 50% HP baseline, adjusted per encounter
- **Resonance rewards per miniboss**: Scaled by Ring difficulty (pending Phase 4b progression tuning)
- **Witnessing mechanic specifics**: Codex entry requirements vs. combat advantage specifics

---

# Integration with Other Systems

### StateService
- Enemy state machines (Idle, Patrol, Aggro, Casting, Dead)
- Synchronized with player state transitions for meaningful combat windows

### HitboxService
- Enemy melee ranges and ability AoE radii
- Hit feedback and impact validation

### AspectService
- Choir ability usage (Ash, Ember, Gale, Tide, Void, Silhouette)
- Elite Choir combining multiple Aspect abilities
- Marrow hints via Choir Adjudicant Phase 2

### CombatService
- Server-authoritative enemy damage calculations
- Miniboss two-phase transitions
- Rate limiting on enemy action frequency

### NetworkService
- Enemy position updates and ability synchronization to all players
- Convergence event triggers and consequences

---

# References

- **Copilot Instructions**: [.github/copilot-instructions.md](../.github/copilot-instructions.md#-enemy--zone-rules)
- **Game Plan**: [Main.md](Main.md)
- **Session Log**: [session-log.md](session-log.md)
- **Related Issues**: [#175](https://github.com/JoshuaKushnir/Nightfall/issues/175) (Enemy AI), [#176](https://github.com/JoshuaKushnir/Nightfall/issues/176) (HUD), [#177](https://github.com/JoshuaKushnir/Nightfall/issues/177) (Dialogue), [#178](https://github.com/JoshuaKushnir/Nightfall/issues/178) (This Design)

