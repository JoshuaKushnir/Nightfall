# NIGHTBOUND � COMPLETE GAME DESIGN DOCUMENT

## THE WORLD & CORE IDENTITY

Vael is a continent in permanent twilight. The Hearthspire city surrounds a failing Solstice Pillar; the light it emits is the last hold against the dark. Rings radiate outward from the Hearthspire, each darker and deadlier. Players are Drifters�twilight-marked beings who can die and return, gain power, and are treated like omens. The core mystery: something has been devouring the light for three centuries, and it may be a decision, not a monster.

## THE DIMMINGS

**Dimmings** are world-wide updates that darken Vael, open a new Ring, and add systems and content. The horizon is always just beyond reach.

1. **First** � *Survival and Identity*: Launch content. Hearthspire and Ring One (Verdant Shelf). Teaches movement, combat, factions, core loop. NPCs hint at the darkness beyond.
2. **Second** � *Corruption and Power*: Unlocks Ring Two (Ashfeld). Omen system activates with Umbral Marks and paths. Introduces Marrow Aspect and the Ashen Choir faction. **Resonance Echoing** makes battles alter terrain temporarily.
3. **Third** � *History and Ruin*: Ring Three (Vael Depths) reveals preserved pre-twilight ruins. Umbral Codex lore pays off. **Memory Fragments** are interactive echoes. New enemies: **The Preserved**.
4. **Fourth** � *The Threshold*: Ring Four (Gloam) has passive luminance drain and no compass markers in PvP. **Dark Adaptation** grants low-light vision but increases risk from luminance-sensitive foes. Ashen Choir shows fear.
5. **Final** � *The Null*: Endgame zone with constant drain. No traditional boss; instead a server-wide **Convergence** event requiring all players and altering the Hearthspire permanently.

## PROGRESSION

* **Resonance** � attunement gained via combat, exploration, crafting, and survival. It gates upgrades, mastery, and ring access. Soft caps per ring force forward momentum. Death costs Shards plus a temporary Luminance debuff.
* **Three pillars**:
  * **Aspect** (future work): Elemental identity with six Aspects at launch, each with Expression, Form, and Communion branches. Cross-Aspect synergies exist.
  * **Discipline** (designed): Four paths�Wayward, Ironclad, Silhouette, Resonant�affect physical capability and weapon mastery. Cross-training is allowed at Resonance cost.
  * **Omen** (future): Marks accumulate through dying, deep exploration, Choir interactions, and Aspect overuse. Five thresholds grant passive corruptions and visibility to others. Cleansing has a cost.

Specification gaps include weapon weight class names, tuning numbers, system parameters (Shard loss, Breath costs, etc.), and several unspecific mechanics.

## MOVEMENT

Sprint, dash, lunge are implemented; wall-run, ledge catch, vault, slide are designed but unbuilt. **Breath** powers actions and recharges when grounded. **Momentum** multiplies movement benefits up to 3� and affects combat if you hit while running. Each Aspect confers a movement tweak (afterimages, wet terrain slide, mid-air redirect, etc.). Environmental traversal is expected knowledge.

## COMBAT � PVP & PVE

PVP systems are partial. Core loop: separate Posture and HP, Break attacks on posture collapse, feinting to bait defenses, and the planned Clash system where simultaneous hits open a follow-up window. Aspect abilities focus on posture. Additional mechanics designed but unimplemented include Condemned status for targets of multiple attackers, Living Resonance streaks, Dueling Grounds, faction flagging, and Last Rites input at death.

PVE is scaffolding only (Dummy NPCs). Enemy design emphasizes readability, telegraphs, and a **Witnessing** system for lore/balance. Designed enemy roster: Hollowed, Duskwalkers, Threadweavers, Ashen Choir, Preserved, Vaelborn. Bosses are story-gated with second-form shifts and pre-encounter interactions. World bosses trigger on server Luminance and are Convergence events.

## DEATH & INCENTIVE

Death enters **The Between** for ~30 seconds; others can revive you by sacrificing Luminance, else you respawn at an Ember Point. Losses: Resonance Shards, consumables, and a Dimming debuff. **The Streak** builds Living Resonance glow and grants bonuses. **Last Rites** allow you to burn shards for your killer�s benefit or leave a permanent light memorial.

## META PROGRESSION

The **Ashen Record** is account-level history tracking kills, duels, factions, exploration, and survival time. It grants permanent **Echoes**�small passive unlocks for new characters�and cosmetic rewards (markings, trails, memorial designs). The **Umbral Codex** is a lore book of entries players collect.

## WORLD & SYSTEMS

Rings: 0 Hearthspire (safe); 1 Verdant Shelf; 2 Ashfeld; 3 Vael Depths; 4 Gloam; 5 Null. Drift Gates handle travel; fast travel tied to faction standing. **Dimming Cycles** periodically darken the world, altering enemy behavior and spawning exclusive content. Server-wide luminance tracking and ring transitions are yet to be specified.

## FACTIONS

Unimplemented. Four factions:

* **Pillar Wardens** � defend the Hearthspire, distrust Omen, control most gates, military.
* **Wandering Court** � traders/explorers, neutral PvP, lore access, diplomacy with Choir.
* **Ashen Choir** � cult accepting Omen, controls Ring Two territory, offers Marrow knowledge.
* **Unmarked** � no faction, gain the Unbound passive but lose faction travel and services.

Faction mechanics, quests, and switching costs are undetailed.

> �The sun didn�t die� keep moving toward it.� � anonymous wall writing in the Vael Depths.
