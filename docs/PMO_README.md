# PMO Subsystem (Session Tracker & Issue Manager)

This repository now includes a small, self‑contained project management office
(PMO) subsystem that the AI automation (Copilot agent) is wired up to.  It
is **not** magical: it simply runs shell scripts that any developer could run
directly.

## How it works

1. Every conversation the agent has is appended to `docs/session-log.md` via
   `session_tracker.sh` (see below).
2. When a new task/issue should be created, the agent emits a special command
   (`gh_issue_sync ...`) which calls the GitHub CLI and creates/comments the
   issue.
3. The same `issue_manager.sh` script is used if the agent needs to change
   status, add progress notes, or generate reports later on.
4. The shell scripts are intentionally tiny; the Copilot agent simply invokes
   them whenever the session log contains an `issue` entry or the session
   tracker returns a `gh` command string.

> **Note:** the "automatic" behaviour you see while interacting with Copilot
> is just these scripts being executed under the covers.  You can reproduce the
> same behaviour by running them yourself.

## Files added

* `session_tracker.sh` – start/update/end a chat session and synchronise with
  GitHub issues via the `gh_issue_sync` helper.
* `issue_manager.sh` – convenience wrapper around `gh issue {create,comment,close,list}`
* Documentation in this directory (see the next section) describing the
  pipeline and reuse instructions.

## Making it reusable in another repository

1. Copy `session_tracker.sh` and `issue_manager.sh` into the new repo.
2. Add the accompanying documentation (this file and
   `PMO_DIRECTORY_STRUCTURE.md`).
3. Configure your automation/agent to:
   * Log every conversation to a simple session log (plain Markdown or a
     database).
   * Detect when a new work item is mentioned (keyword scans, natural language
     parsing, or explicit `/issue` commands).
   * Call `session_tracker.sh sync create "title" "body"` or
     `issue_manager.sh create …` as appropriate and record the resulting
     issue number back in the log.
   * Optionally run a dashboard generator (`generate_dashboard.sh` in this
     repo) to produce metrics.
4. Every time your automation writes a `session_tracker.sh` entry tagged
   `issue` the scripts will run and a GitHub issue will be created automatically.

### Optional Python wrapper

If you prefer Python, below is a minimal wrapper you can plug into your
chat/agent code:

```python
#!/usr/bin/env python3
import subprocess

def gh_issue_sync(action, *args):
    cmd = ['bash', 'session_tracker.sh', 'sync', action] + list(args)
    return subprocess.run(cmd, check=False, capture_output=True).stdout

# example usage
print(gh_issue_sync('create', 'New feature', 'Implement X in repo Y'))
```

Modify as needed to run on Windows or another shell.

---

For more documentation and examples of the chat→issue pipeline see
`docs/PMO_DIRECTORY_STRUCTURE.md` and the existing `docs/session-log.md` file.
