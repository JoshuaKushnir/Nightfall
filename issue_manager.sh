#!/bin/bash
# issue_manager.sh
#
# Simplified wrapper around GitHub CLI for creating and manipulating issues.
# Called by automation (Copilot/agents) when they decide a new task/epic
# should be created or updated.

function create() {
    gh issue create "$@"
}

function comment() {
    gh issue comment "$@"
}

function close() {
    gh issue close "$@"
}

function list() {
    gh issue list "$@"
}

case "$1" in
    create|comment|close|list)
        action="$1"; shift
        $action "$@"
        ;;
    *)
        echo "Usage: $0 {create|comment|close|list} [args]" >&2
        exit 2
        ;;
esac
