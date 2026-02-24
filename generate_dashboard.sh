#!/bin/bash
# generate_dashboard.sh
# optional helper that reads docs/session-log.md and produces simple metrics.

LOGFILE="docs/session-log.md"
OUT="docs/dashboard.md"

echo "# Dashboard" > "$OUT"
echo "- total lines: $(wc -l < "$LOGFILE")" >> "$OUT"
echo "- last updated: $(date)" >> "$OUT"

echo "(This is a placeholder; extend as needed.)" >> "$OUT"
