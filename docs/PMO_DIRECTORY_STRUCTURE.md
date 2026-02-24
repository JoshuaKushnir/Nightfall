# PMO Directory Structure

This document explains where the PMO-related scripts and logs live, along with
an outline of their responsibilities.

```
Nightfall/               # root of project
  session_tracker.sh     # start/update/end sessions, sync issues
  issue_manager.sh       # thin wrapper around gh issue
  docs/
    session-log.md       # chronological log of AI sessions and notes
    PMO_README.md        # this file (high-level overview)
    PMO_DIRECTORY_STRUCTURE.md  # you are reading it now
    ... other game docs ...
```

## session_tracker.sh

* `start`, `update`, `end` commands append to `docs/session-log.md`.
* `sync` subcommand calls the `gh_issue_sync` helper which formats a
  `gh issue create` or `gh issue comment` invocation.  The agent simply passes
  through whatever it thinks should run; the script gives us a single place to
  stub or log the command for debugging.
* Typical usage by the Copilot agent:
  ```bash
  session_tracker.sh start
  session_tracker.sh update "User wants to add TODO: balance stamina"
  session_tracker.sh sync create "Balance stamina" "Implement via new subsystem"
  session_tracker.sh end
  ```

## issue_manager.sh

A thin wrapper around common `gh issue` operations.  Provides a uniform CLI for
agents attempting to create epics, tasks, add progress comments, close issues,
etc.  The script exists primarily as a stable target for automation rather than
for human use, but it’s simple enough to use directly:

```bash
issue_manager.sh create --title "Write tests" --body "…"
issue_manager.sh comment 123 --body "Added unit tests."
issue_manager.sh close 123
issue_manager.sh list --label open
```

## Reusing the subsystem

The instructions in `PMO_README.md` show how to integrate these scripts into
any repository.  The only real requirement is that the AI/automation you use
must know when to call the scripts; that logic lives in your agent code and is
completely separate from the contents of this directory.
