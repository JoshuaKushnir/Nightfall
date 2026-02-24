#!/bin/bash
# session_tracker.sh
#
# Lightweight session tracking script used by the PMO subsystem.
# Every time an agent conversation begins/updates/ends we log entries and
# optionally invoke GitHub CLI commands.  This is the same code Copilot
# exercises when it "automatically" creates issues for us.

LOGFILE="docs/session-log.md"

function start_session() {
    echo "## Session started at $(date)" >> "$LOGFILE"
}

function update_session() {
    # append arbitrary text to the session log
    echo "[")$(date)"] $*" >> "$LOGFILE"
}

function end_session() {
    echo "## Session ended at $(date)" >> "$LOGFILE"
}

# helper used by the agent when it decides to create/update an issue.
# it simply translates a small DSL of actions into gh commands.
function gh_issue_sync() {
    # usage: gh_issue_sync <action> <args...>
    local action="$1"; shift
    case "$action" in
        create)
            # gh issue create --title "$1" --body "$2" [...]
            gh issue create --title "$1" --body "$2" "${@:3}"
            ;;
        comment)
            # gh issue comment <issue-number> --body "..."
            gh issue comment "$1" --body "$2"
            ;;
        *)
            echo "gh_issue_sync: unknown action '$action'" >&2
            return 1
            ;;
    esac
}

case "$1" in
    start) shift; start_session "$@" ;;    # nothing else required
    update) shift; update_session "$@" ;;  # pass freeform text
    end) shift; end_session "$@" ;;        # close a session
    sync) shift; gh_issue_sync "$@" ;;     # call the helper directly
    *)
        echo "Usage: $0 {start|update|end|sync} ..." >&2
        exit 2
        ;;
esac
