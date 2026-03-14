#!/bin/zsh
# heartbeat.sh — Claude calls this to write a heartbeat and sync workspace to git.
# Usage: ./heartbeat.sh "phase" "task description" ["2026-03-14T15:30:00" for scheduled restart]
#
# Call this:
#   - At the start of every session
#   - After every major action
#   - Before any long-running operation
#   - When setting a known restart time (rate limit, etc.)

WORKSPACE="$(dirname "$(realpath "$0")")"
TASKS="$WORKSPACE/tasks"
HEARTBEAT="$TASKS/heartbeat.json"

PHASE="${1:-unknown}"
TASK="${2:-unknown}"
SCHEDULED_RESTART="${3:-}"  # ISO8601 datetime, optional

NOW=$(date +%s)
NOW_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

python3 - << EOF
import json

data = {
    "timestamp": $NOW,
    "timestamp_human": "$NOW_HUMAN",
    "phase": "$PHASE",
    "task": "$TASK",
    "scheduled_restart": "$SCHEDULED_RESTART"
}

with open("$HEARTBEAT", "w") as f:
    json.dump(data, f, indent=2)
print(f"[heartbeat] {data['timestamp_human']} | {data['phase']} | {data['task']}")
EOF

# Sync workspace to git (optional — remove if you don't want auto-push)
cd "$WORKSPACE" || exit 1
git add -A
if ! git diff --cached --quiet; then
    git commit -m "sync: $PHASE — $TASK ($NOW_HUMAN)"
    git push origin main > /dev/null 2>&1 && echo "[heartbeat] Pushed." || echo "[heartbeat] Push failed (non-fatal)."
else
    echo "[heartbeat] No changes to push."
fi
