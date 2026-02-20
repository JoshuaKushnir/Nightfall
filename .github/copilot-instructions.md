# Nightfall: Engineering Manifesto & Architecture Rules

## 1. System Memory & Session Tracking
- **Session Log:** Before every task, READ `docs/session-log.md`. After every task, UPDATE it with completed work, new types created, and pending technical debt.
- **Context Preservation:** Always reference `src/shared/types` to ensure data structures remain consistent across the server/client boundary.

## 2. Modular Architecture (Rojo/Luau)
- **Service/Controller Pattern:** - Server logic lives in `src/server/services`. 
    - Client logic lives in `src/client/controllers`.
    - No direct cross-talk; use `src/shared/network` for Remote communication.
- **Dependency Injection:** Services must be initialized via an `Init` or `Start` method. Do not use `wait()` for loading; use a signal-based provider.
- **DRY Utility First:** If logic is used twice (e.g., Magnitude checks, Raycasts), it MUST move to `src/shared/modules/Utils`.

## 3. Combat & Gameplay Logic
- **State-Machine Authoritative:** Every character (NPC/Player) must have a `State` entry in the `StateService`. 
- **Action Validation:** - `if State == "Stunned" then return`
    - `if State == "Attacking" then return`
- **Mantra Framework:** Mantras are modular objects. A Mantra must contain: `BaseDamage`, `CastTime`, `Cooldown`, and a `VFX_Function`.

## 4. Coding Standards
- **Typing:** Strict typing mandatory (`--!strict`). Use `export type` for all data schemas.
- **Composition:** Avoid large "Player" classes. Use a `Component` system for attributes like `Health`, `Mana`, and `Posture`.
- **Boilerplate:** Every new module must include the standard documentation header (Class, Description, Dependencies).

## 5. Issue Management & Dependencies
- **Issue Linking:** Use GitHub's "Linked Issues" feature (not manual text in description) to mark issue dependencies.
  - **How to Link Issues:**
    1. Open the issue on GitHub web
    2. Scroll to "Linked issues" section (right sidebar)
    3. Click "Add linked issue"
    4. Select relationship type: **"blocks"** (this issue blocks another) or **"blocked by"** (this issue is blocked by another)
    5. Enter the issue number to link
  - **When to Use:**
    - Use `blocks` when your issue must be completed before another can start
    - Use `blocked by` when your issue depends on another issue being completed first
  - **Dependency Format:** Use `Requires #24` or similar in description ONLY for documentation/clarity. Always back it up with actual Linked Issues.
  - **Removal:** Remove manual "Requires" text from descriptions once linked issues are created via GitHub UI.

## 6. Issue Creation Standards
- **Milestones/Phases:** Always assign the appropriate milestone corresponding to the project phase (Phase 1-5 as defined in the roadmap).
- **Labels:** Apply relevant labels including:
  - Phase label: `phase-1`, `phase-2`, `phase-3`, `phase-4`, or `phase-5`
  - Priority label: `critical`, `high`, `medium`, or `low`
  - Type label: `infrastructure`, `data`, `combat`, `magic`, `ui`, `networking`, `testing`, etc.
- **Parents:** If the issue is a sub-issue or child of another, link it as 'blocked by' the parent issue using GitHub's linked issues.
- **Blocked Status:** If the issue is blocked by another issue, immediately mark it as 'blocked by' the blocking issue(s) using GitHub's linked issues feature.

## 7. Copilot / Automated Contributor Behavior
- **Purpose:** Define expected behavior for automated assistance (GitHub Copilot / bots) while working on issues and pull requests.
- **Frequent Issue Updates:** While actively working on an issue, Copilot must post progress updates to the GitHub issue **immediately whenever a major change to the issue occurs**. "Major changes" include (but are not limited to):
  - Checklist items added, checked, unchecked, or removed
  - Linked sub-issues (linked/blocked/blocked-by) added, removed, or re-linked
  - Acceptance criteria or checklist modifications
  - Labels, priority, milestone, or assignee changes
  - PR state changes (opened, draft → ready, merged, closed)
  - Significant commits or tests that alter scope or behavior

  For every major change, the update should:
  - Briefly describe the change and why it was made
  - Call out affected checklist items or linked sub-issues (with links)
  - List next steps and any remaining blockers
  - Link to related commits/PRs and session-log entries

  - For long-running tasks, leave a status comment at least every 48 hours.
- **Commit & Push Frequency:**
  - Make small, atomic commits that implement a single logical change. Prefer frequent commits over monolithic ones.
  - Push commits to the feature branch after each self-contained change (function/feature completed, test added/fixed, refactor step) and at minimum at the end of each work session.
  - Commit messages MUST reference the issue number (e.g. `#98`) and be concise and imperative.
- **PR Workflow:**
  - Open a draft PR early for non-trivial work and update it as progress is made; always link the PR to the issue.
  - Update the issue whenever the PR status changes (draft → ready, CI failures, reviews addressed).
- **Session-log Coordination:**
  - Continue to update `docs/session-log.md` before/after tasks. Each entry should reference the issue and/or PR and a short summary of changes.
- **Human-readable Automation:**
  - Automated comments/updates must be clear, actionable, and avoid noisy or repetitive messages.
  - If automation cannot push (permissions/network), post an issue comment explaining the blocker.

# docs/session-log.md (The Memory File)
Always update this file so you remember what you've built. Include issue/PR links and a short summary in each session entry.