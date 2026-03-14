#!/bin/zsh
# brief.sh — generates and sends a daily briefing.
#
# Reads session logs and workspace state to produce a brief that reflects
# what actually happened. Sends via Pushover and writes full detail to
# tasks/BRIEF.md.
#
# Called by launchd at 8am daily, or manually: ./brief.sh

WORKSPACE="$(dirname "$(realpath "$0")")"
TASKS="$WORKSPACE/tasks"
BRIEF_FILE="$TASKS/BRIEF.md"
HEARTBEAT="$TASKS/heartbeat.json"
DATE_LABEL=$(date '+%a %b %-d')
NOW=$(date '+%Y-%m-%d %H:%M')

source ~/.pushover_secrets 2>/dev/null

push() {
    local title="$1" msg="$2" priority="${3:-0}"
    [ -z "$PUSHOVER_TOKEN" ] && { echo "[brief] Pushover not configured — skipping notification."; return; }
    curl -s \
        --form-string "token=$PUSHOVER_TOKEN" \
        --form-string "user=$PUSHOVER_USER" \
        --form-string "title=$title" \
        --form-string "message=$msg" \
        --form-string "priority=$priority" \
        https://api.pushover.net/1/messages.json > /dev/null 2>&1
}

# ── Gather state ─────────────────────────────────────────────────────────────

# Last heartbeat
if [ -f "$HEARTBEAT" ]; then
    hb_phase=$(python3 -c "import json; print(json.load(open('$HEARTBEAT')).get('phase','unknown'))")
    hb_task=$(python3 -c "import json; print(json.load(open('$HEARTBEAT')).get('task','unknown'))")
    hb_time=$(python3 -c "import json; print(json.load(open('$HEARTBEAT')).get('timestamp_human','unknown'))")
else
    hb_phase="no heartbeat"
    hb_task="unknown"
    hb_time="unknown"
fi

# Session logs written since last brief (or last 24h)
recent_sessions=$(find "$TASKS/repos" -name "*.md" -path "*/sessions/*" -newer "$BRIEF_FILE" 2>/dev/null | sort)
[ -z "$recent_sessions" ] && recent_sessions=$(find "$TASKS/repos" -name "*.md" -path "*/sessions/*" | sort | tail -3)

# Any open questions in recent sessions
open_questions=""
while IFS= read -r session; do
    [ -z "$session" ] && continue
    q=$(awk '/^## Open Questions/{found=1; next} found && /^## /{found=0} found && /[^[:space:]]/{print}' "$session" 2>/dev/null | head -3)
    [ -n "$q" ] && open_questions="$open_questions\n$q"
done <<< "$recent_sessions"

# Git log since last 24h
recent_commits=$(cd "$WORKSPACE" && git log --since="24 hours ago" --oneline 2>/dev/null | head -6)

# ── Decide what this brief is about ──────────────────────────────────────────
has_blocker=false
[ -f "$TASKS/BLOCKER.md" ] && has_blocker=true
has_question=false
[ -n "$open_questions" ] && has_question=true

# ── Write full BRIEF.md ──────────────────────────────────────────────────────
cat > "$BRIEF_FILE" << EOF
---
date: $(date '+%Y-%m-%d')
phase: $hb_phase
---
# Daily Brief — $NOW

## Status
**Last active:** $hb_time
**Phase:** $hb_phase
**Task:** $hb_task

## Work Since Last Brief
$(if [ -n "$recent_commits" ]; then
    echo "$recent_commits" | sed 's/^/- /'
else
    echo "- No commits in last 24h"
fi)

## Session Logs
$(if [ -n "$recent_sessions" ]; then
    echo "$recent_sessions" | while IFS= read -r s; do echo "- $(basename $(dirname $s))/$(basename $s)"; done
else
    echo "- No new sessions"
fi)

## Open Questions
$([ -n "$open_questions" ] && echo -e "$open_questions" || echo "None.")

## Blocker
$([ -f "$TASKS/BLOCKER.md" ] && cat "$TASKS/BLOCKER.md" || echo "None.")
EOF

# ── Build Pushover message ──────────────────────────────────────────────────
build_push_msg() {
    local msg=""

    if $has_blocker; then
        blocker_title=$(head -1 "$TASKS/BLOCKER.md" | sed 's/# //')
        msg="BLOCKER: $blocker_title\n\n"
    fi

    if [ -n "$recent_commits" ]; then
        commit_count=$(echo "$recent_commits" | wc -l | tr -d ' ')
        last=$(echo "$recent_commits" | head -1 | cut -c9-)
        msg="${msg}$commit_count commit(s) — latest: $last\n"
    else
        msg="${msg}No commits today\n"
    fi

    if [ "$hb_phase" != "no heartbeat" ] && [ "$hb_phase" != "complete" ]; then
        msg="${msg}> $hb_phase: $hb_task\n"
    fi

    if $has_question; then
        first_q=$(echo -e "$open_questions" | grep -m1 '[^[:space:]]')
        msg="${msg}Open: $first_q\n"
    fi

    echo -e "$msg" | head -c 950
}

PUSH_MSG=$(build_push_msg)
PUSH_TITLE="Brief — $DATE_LABEL"

push "$PUSH_TITLE" "$PUSH_MSG"

# Archive dated copy
DATED_BRIEF="$TASKS/briefs/$(date '+%Y-%m-%d').md"
mkdir -p "$TASKS/briefs"
cp "$BRIEF_FILE" "$DATED_BRIEF"

# Commit the brief
cd "$WORKSPACE"
git add "$BRIEF_FILE" "$DATED_BRIEF"
if ! git diff --cached --quiet; then
    git commit -m "brief: daily summary $NOW"
    git push origin main > /dev/null 2>&1
fi

echo "[brief] Sent: $PUSH_TITLE"
echo "[brief] Full brief written to $BRIEF_FILE"
