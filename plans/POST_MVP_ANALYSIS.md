# Post-MVP Issues Analysis with AAA Recommendations

## Post-MVP Labeled Issues

### Issue #82: Ring Structure + Luminance Drain Zones
**Created:** 2026-02-18  
**Labels:** post-mvp, medium, infrastructure, backend, systems, enhancement

#### AAA Standards Review Findings:

**Monetization & Live Operations:**
- ⚠️ **Gap**: This system introduces Ring-based content gating that could be leveraged for live ops events
- Recommendation: Design "Dimming Cycle" events around Ring transitions (as noted in game plan)
- Consider: Ring-limited time events for monetization

**Accessibility:**
- ⚠️ **Gap**: No accessibility consideration for Luminance system
- Recommendation: Add "Luminance Display Option" for color-blind players (high contrast mode)
- Consider: Luminance drain rate accessibility setting

**Performance:**
- Recommendation: Zone detection should use spatial hashing or region3 efficiently
- Implement: Caching as noted, avoid heartbeat position checks every frame

**Audio:**
- ⚠️ **Gap**: No audio design for zone transitions
- Recommendation: Add ambient audio transitions between Rings
- Consider: Sound design for Luminance drain warning

**Technical Debt:**
- Zone detection using region volumes - need efficient spatial partitioning
- Luminance persistence via DataService (blocked by #24) - ensure proper migration path

---

### Issue #79: Omen System — Dark Accumulation, 5 Mark Thresholds
**Created:** 2026-02-18  
**Labels:** post-mvp, medium, magic, mantras, progression, backend, mechanics

#### AAA Standards Review Findings:

**Visual Fidelity:**
- ⚠️ **Critical Gap**: Visual corruption layers require VFX implementation
- Recommendation: Plan character effect shader system
- Current: Placeholder models acceptable - need roadmap to full implementation
- See: .cursorrules VFX stub requirement

**Accessibility:**
- ⚠️ **Gap**: Visual corruption at Mark 5 may affect visibility
- Recommendation: Ensure visual effects are distinguishable for color-blind players
- Consider: Alternative indicators for PvP tells beyond visual only

**User Experience:**
- Recommendation: Add Omen UI display (similar to Resonance HUD)
- Consider: Notification system for threshold crossings

**Technical Debt:**
- OmenService needs to integrate with existing DeathService (#144)
- Faction system dependency (#12) - need to plan integration

---

## Critical & High Priority Issues - UPDATE: #173 ALREADY IMPLEMENTED

### Issue #173: Progression System - XP, Leveling, Stat Allocation
**Created:** 2026-03-10 (Newest)  
**Labels:** high, phase-4, progression, enhancement

**Status:** ⚠️ APPEARS TO BE MOSTLY IMPLEMENTED - Needs verification

**Finding:** All required files exist:
- ✅ ProgressionTypes.lua - types defined
- ✅ ProgressionService.lua (20KB) - server implementation  
- ✅ ProgressionController.lua (17KB) - client implementation
- ✅ ProgressionService.test.lua - comprehensive unit tests

**Acceptance Criteria Status:**
- [?] XP is awarded for combat actions - Need to verify integration with CombatService
- [?] Players can level up and receive stat points - Likely complete
- [?] Stat points can be allocated and persist - Likely complete
- [✅] Unit tests cover XP calculations and level logic - Tests exist!
- [?] Session log updated and issue linked - Need verification

**Recommendation:** Verify the issue is actually complete by running tests and checking session log. This may be a case where the issue should be closed.

---

### Issue #148: First Diming MVP Epic
**Created:** 2026-03-02  
**Labels:** mvp, epic, phase-4

**Priority:** CRITICAL - Blocker for release

**Sub-issues that need work:**
- #107 Playable Ring-1 zone
- #123-127 Depth-1 Expression abilities
- #141 Character creation
- #142 Zone trigger system
- #143 HollowedService
- #144 Death respawn flow
- #145-147 HUD improvements

---

## Spec Gap Issues (Lower Priority but Technical Debt)

| Issue | Title | Priority | AAA Impact |
|-------|-------|----------|------------|
| #111 | Aspect branch Shard costs | Low | Balance |
| #112 | Aspect ability Mana costs | Low | Balance |
| #113 | Aspect Expression damage | Low | Balance |
| #114 | Cross-Aspect synergy | Low | Balance |
| #115 | Marrow unlock | Low | Content |
| #129 | Shard death loss formula | Medium | Economy |
| #130 | Discipline stat tables | Medium | Balance |
| #131 | Omen accumulation rates | Medium | Balance |

---

## Recommended Priority Order for Post-MVP Work

1. **Phase 1: MVP Completion** (Issues #148, #173)
   - First Dimming MVP features
   - Progression system

2. **Phase 2: Core Post-MVP Infrastructure** (Issue #82)
   - Ring system architecture
   - Luminance system
   - Zone detection

3. **Phase 3: Progression Expansion** (Issue #79)
   - Omen system
   - Visual effects pipeline

4. **Phase 4: Technical Debt** 
   - Resolve spec gaps (#111-131)

---

## Technical Debt Items from AAA Review

1. **Accessibility Infrastructure** (Critical for AAA)
   - Settings menu with accessibility options
   - Color blind modes
   - Reduced motion option
   - Scalable UI

2. **Audio System**
   - Centralized AudioService
   - Spatial audio
   - Zone-based ambient music
   - Volume controls

3. **Monetization**
   - Game Pass integration
   - Developer Products
   - Premium features

4. **Live Operations**
   - Analytics/telemetry
   - Event system
   - Hotfix infrastructure

5. **Performance**
   - Object pooling
   - Spatial partitioning for zone detection
   - Render optimization
