# NIGHTBOUND – GAME DESIGN OVERVIEW

This document distills the core concepts and systems for Nightbound, transforming the original full‑length design into a digestible one‑pass reference. A newcomer should be able to skim it and grasp the world, progression loops, and current implementation status.

---

## 🌍 World & Identity

**Vael** is a continent trapped in twilight. The last light comes from a failing Solstice Pillar at **Hearthspire**. Rings radiate outward from the city, each darker and more dangerous than the last. Players inhabit the role of **Drifters**: twilight‑marked beings who repeatedly die and return, grow stronger with each return, and are feared as omens. The central mystery is not only what is devouring the light, but whether the darkness itself is a choice.

**[→ Comprehensive World & Enemy Roster Design](World_Design.md)** — Full specifications for all zones, enemy types, minibosses, and world atmosphere across all four rings.

---

## 🔥 The Dimmings (Content Phases)

Each “Dimming” is a major world update that pushes the horizon outward and introduces new mechanics.

1. **First – Survival & Identity**
   * Launch content: Hearthspire and Ring One (Verdant Shelf).  
   * Teaches core movement, combat, faction interaction, and the death‑return loop.  
   * NPCs hint at the threat beyond the safety of light.

2. **Second – Corruption & Power**
   * Opens Ring Two (Ashfeld).  
   * Introduces the **Omen system**: Umbral Marks accumulate through death and risky actions, branching into passive penalties or boons.  
   * Adds the **Marrow Aspect** and the **Ashen Choir** faction.  
   * **Resonance Echoing**: battles temporarily reshape terrain.

3. **Third – History & Ruin**
   * Ring Three (Vael Depths) reveals pre‑twilight ruins and pays off lore in the **Umbral Codex**.  
   * **Memory Fragments** allow players to interact with echoes of the past.  
   * New enemies: **The Preserved**.

4. **Fourth – The Threshold**
   * Ring Four (Gloam) applies a passive luminance drain and removes compass markers during PvP.  
   * **Dark Adaptation** grants low‑light vision while increasing susceptibility to luminance‑sensitive foes.  
   * The Ashen Choir grows wary.

5. **Final – The Null**
   * End‑game zone with unrelenting drain.  
   * There is no single “boss”; instead a server‑wide **Convergence** event requires all players and permanently alters Hearthspire.

---

## ⚙️ Progression Systems

Everything ties back to **Resonance**, the universal currency earned by combat, exploration, crafting, and surviving. It gates upgrades, Aspect mastery, and access to deeper rings. Death costs Shards and applies a temporary luminance debuff. Soft caps per ring ensure forward momentum.

The progression loop is fundamentally about **the cost of knowledge**. Every ring asks the player to understand something harder than the previous:

* **Ring 0 (Hearthspire)** – Understand who you are (Aspect identity, world orientation)
* **Ring 1 (Verdant Shelf)** – Understand what you were (Hollowed as former Drifters, pattern reading through Witnessing)
* **Ring 2 (Ashfeld)** – Understand what you're becoming (Omen corruption, faction allegiance, political consequences)
* **Ring 3 (Vael Depths)** – Understand what the world was (Memory Fragments, pre-twilight lore, Codex interpretation)
* **Ring 4 (Gloam)** – Understand what you're capable of losing (Luminance drain, Streak significance, identity persistence)
* **Ring 5 (The Null)** – Understand what the darkness actually is (Convergence, collective authorship, endgame legacy)

**[→ Full Ring Progression Loop Design](Ring_Progression_Loop.md)**

### Three Pillars of Growth

* **Aspect** *(future work)* – Elemental identities (six at launch) each with three branches: Expression (active ability), Form (passive), and Communion (group utility). Cross‑Aspect synergies are planned.
* **Discipline** *(designed & partially implemented)* – Four physical paths (Wayward, Ironclad, Silhouette, Resonant) that alter movement, combat, and weapon mastery. You can cross‑train by spending Resonance.
* **Omen** *(future)* – Marks accrue from dying, deep exploration, Choir choices, and overusing Aspects. Five thresholds grant passive corruptions visible to others; cleansing has a cost. Introduced at Ring 2, crystallizes into permanent choice at Ring 4.

> ⚠️ **Spec gaps** include weapon weight classes, tuning numbers, shard loss on death, breath costs, and similar parameters. Each gap must spawn a `spec-gap` issue with a placeholder value.

---

## 🏃 Movement

Implemented: sprint, dash, lunge.  
Designed but unbuilt: wall‑run, ledge catch, vault, slide.  
**Breath** powers actions and recharges when grounded.  
**Momentum** multiplies movement benefits up to ×3 and grants combat bonuses when hitting while moving.  
Each Aspect changes movement behavior (e.g. afterimages, slippery terrain, mid‑air redirects).  
Environmental traversal is assumed knowledge—not hand‑held tutorials.

---

## ⚔️ Combat (PvP & PvE)

Core PvP loop separates **Posture** and HP, with *Break* attacks shattering posture.  Feints bait defenses; the planned **Clash** system (simultaneous hits) opens follow‑up windows. Aspects focus on posture manipulation.

Unimplemented concepts: **Condemned** status (multiple attackers), **Living Resonance** streak bonuses, **Dueling Grounds**, faction flagging, Last‑Rites input at death.

PvE currently has only dummy mobs. Design principles include readable telegraphs and a **Witnessing** system for lore/balance. Enemy roster: Hollowed, Duskwalkers, Threadweavers, Ashen Choir, Preserved, Vaelborn. Boss fights are story‑gated with two‑phase encounters and pre‑fight lore scenes. World bosses spawn based on server luminance and trigger Convergences.

---

## ☠️ Death & Incentives

Dying sends you to **The Between** for ~30 seconds. Allies can revive you by sacrificing luminance; otherwise you respawn at an Ember Point.  
Penalties: Resonance Shards, consumables, a “dimming” debuff.  
**The Streak** tracks consecutive lives, granting Living Resonance glow and bonuses.  
**Last Rites** let you burn Shards for your killer’s benefit or leave a permanent light memorial.

---

## 📘 Meta Progression

* **Ashen Record** – account‑wide stats (kills, duels, exploration, survival time). Grants permanent **Echoes** (tiny passive unlocks for new characters) and cosmetics (markings, trails, memorials).
* **Umbral Codex** – lore entries collected during exploration.

---

## 🌐 World & Systems

Rings: 0 Hearthspire (safe) → 1 Verdant Shelf → 2 Ashfeld → 3 Vael Depths → 4 Gloam → 5 Null.  
**Drift Gates** handle travel; fast travel is gated by faction standing.  
**Dimming Cycles** periodically darken areas, altering enemy behavior and spawning exclusive content.  
Server‑wide **luminance** drives ring transitions; exact mechanics are TBD.

---

## 🛡️ Factions *(Unimplemented)*

Four factions shape politics and travel:

* **Pillar Wardens** – hearth defenders, anti‑Omens, gate controllers.
* **Wandering Court** – neutral traders/explorers; diplomacy with Choir.
* **Ashen Choir** – Omen‑embracers controlling Ashfeld, offering Marrow knowledge.
* **Unmarked** – no faction; gain the Unbound passive but lose faction services.

Faction mechanics, quests, and switching costs remain unspecified.

---

> “The sun didn’t die—keep moving toward it.”  
> – anonymous wall writing in the Vael Depths

---

This overview ensures first‑time readers can understand the state of the project in one pass.
