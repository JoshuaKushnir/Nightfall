# Issue Board Cleanup Guide: Converting Manual Dependencies to GitHub Linked Issues

## Status
- ✅ Copilot instructions updated with linking procedure
- ⏳ Waiting for manual test on first issue
- ⏳ Bulk cleanup of remaining issues

## Test Issue
**Start here to test the workflow:**
- Issue: #42 - Client-Side Binding Framework & State Sync UI
- Current dependencies (manual):
  - Requires #24 (ProfileService Data Wrapper)
  - Requires #25 (Enhanced State Machine System)  
  - Requires #26 (Network Provider)

### Test Steps
1. Go to https://github.com/JoshuaKushnir/Nightfall/issues/42
2. Scroll to the right sidebar → "Linked issues" section
3. Click "Add linked issue"
4. Select relationship: **"blocked by"** (because #42 is blocked by the other issues)
5. Enter issue number: 24, then 25, then 26
6. After creating links, edit issue body and remove the manual "Requires" lines

## Issues Requiring Cleanup
These issues have manual dependency text that needs to be converted:

| Issue | Title | Dependencies to Link |
|-------|-------|---------------------|
| #47 | Equipment Inventory & Loadout UI | Blocked by: #36, #35 |
| #46 | Character Sheet & Stat Display UI | Blocked by: #35, #36 |
| #45 | Mantra VFX & Animation System | Blocked by: #31, #42 |
| #44 | Mantra Casting UI & Keybind System | Blocked by: #31, #32, #33 |
| #43 | Combat Feedback UI | Blocked by: #28, #30, #29 |
| #42 | Client-Side Binding Framework | **TEST ISSUE** - Blocked by: #24, #25, #26 |
| #41 | Runtime Bootstrap Scripts Missing | Has "Dependencies" section |
| #40 | Launch Preparation & Deployment | Analyze for dependencies |
| #39 | UI/UX Responsive Framework | Analyze for dependencies |
| #38 | Performance Optimization | Analyze for dependencies |
| #37 | DataStore Fail-Safes & Analytics | Analyze for dependencies |
| #36 | Armor/Class Component System | Analyze for dependencies |
| #35 | Progression & Leveling System | Analyze for dependencies |
| #34 | Branching Dialogue System | Analyze for dependencies |
| #33 | Global Cooldown & Mana Management | Analyze for dependencies |
| #32 | Multi-Element/Class Logic | Analyze for dependencies |
| #31 | Dynamic Mantra Loader | Analyze for dependencies |

## Workflow
1. **Test**: Complete test on issue #42
2. **Update**: Remove manual dependency text from issue #42 description
3. **Bulk Cleanup**: Apply same pattern to all other issues
4. **Verify**: Check that all Linked Issues are properly configured
5. **Documentation**: Link issues are now machine-readable and visible in project planning

## GitHub Linked Issues Relationship Types
- **blocks**: This issue must be completed before another can start
- **blocked by**: This issue depends on another being completed first
- **relates to**: This issue is related to another (informational)
- **duplicates**: This issue is a duplicate of another

## Benefits of Linked Issues
✓ Automatically visible in GitHub project boards
✓ Prevents accidental merging of blocked issues
✓ Creates dependency graph for better planning
✓ Works with GitHub's automation and workflows
✓ Machine-readable for tools and scripts
