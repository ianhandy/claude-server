#!/bin/zsh
# executor.sh — runs a single queued task headlessly via claude --print.
# Called by watchdog.sh when a PENDING task is found.
# Usage: ./executor.sh tasks/queue/PENDING-YYYYMMDDHHMM-slug.md

WORKSPACE="$(dirname "$(realpath "$0")")"
TASKS="$WORKSPACE/tasks"
TASK_FILE="$1"

[ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ] && { echo "Usage: executor.sh <task-file>"; exit 1; }

TASK_SLUG=$(basename "$TASK_FILE" .md)
REPO=$(awk '/^repo:/{print $2}' "$TASK_FILE" | tr -d ' ')
REPO=${REPO:-uncategorized}
REPO_PATH="${REPOS_DIR:-$HOME/repos}/$REPO"
SESSION_DATE=$(date '+%Y-%m-%d')
SESSION_SLUG=$(echo "$TASK_SLUG" | sed 's/PENDING-[0-9]*-//')
LOG_DIR="$TASKS/repos/$REPO/sessions"
LOG_FILE="$LOG_DIR/${SESSION_DATE}_${SESSION_SLUG}.md"
LOCK="$TASKS/ACTIVE_TASK"

mkdir -p "$LOG_DIR"

# ── Set lock ─────────────────────────────────────────────────────────────────
echo "$TASK_SLUG" > "$LOCK"

# ── Initial heartbeat ────────────────────────────────────────────────────────
"$WORKSPACE/heartbeat.sh" "executor-start" "$TASK_SLUG"

# ── Build prompt ─────────────────────────────────────────────────────────────
CLAUDE_MD=$(cat "$WORKSPACE/CLAUDE.md")
TASK_CONTENT=$(cat "$TASK_FILE")
RECENT_INDEX=""
if [ -f "$TASKS/repos/$REPO/INDEX.md" ]; then
    RECENT_INDEX=$(cat "$TASKS/repos/$REPO/INDEX.md")
fi

PROMPT="You are running autonomously and headlessly. No human is present. Your operator will read your session log later.

## Your Standing Orders
$CLAUDE_MD

## Repo Index (for context)
$RECENT_INDEX

## Task to Execute
$TASK_CONTENT

## Execution Rules
- Write heartbeats at each major step: ./heartbeat.sh \"phase\" \"description\"
- Work only in $REPO_PATH (or workspace if no repo)
- Commit your work with clear messages
- Write your full session log to: $LOG_FILE
  Use the standard log format from CLAUDE.md
- Add your keywords to: $TASKS/repos/$REPO/INDEX.md
- When done: move $TASK_FILE to $TASKS/queue/done/DONE-${TASK_SLUG}.md
- If blocked: write $TASKS/BLOCKER.md with reason, then send Pushover
- Do NOT ask questions. Make a decision, log your reasoning, proceed.

Begin now."

# ── Run Claude headlessly ────────────────────────────────────────────────────
echo "[executor] Starting task: $TASK_SLUG at $(date '+%H:%M:%S')" >> "$TASKS/watchdog.log"

claude --dangerously-skip-permissions \
    --add-dir "$WORKSPACE" \
    --add-dir "$REPO_PATH" \
    -p "$PROMPT" >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# ── Check for blocker written by Claude during the task ───────────────────────
if [ -f "$TASKS/BLOCKER.md" ] && [ ! -f "$TASKS/BLOCKER_RESPONSE.md" ]; then
    BLOCKER_TITLE=$(head -1 "$TASKS/BLOCKER.md" | sed 's/# //')
    echo "[executor] Blocker detected: $BLOCKER_TITLE — parking task, continuing queue" >> "$TASKS/watchdog.log"

    # Park the blocked task
    mkdir -p "$TASKS/queue/blocked"
    PARKED="$TASKS/queue/blocked/BLOCKED-${TASK_SLUG}.md"
    [ -f "$TASK_FILE" ] && mv "$TASK_FILE" "$PARKED"

    # Write a sidecar linking the blocker to the parked task
    echo "PARKED_TASK=$PARKED" >> "$TASKS/BLOCKER.md"

    # Notify via Pushover
    source ~/.pushover_secrets 2>/dev/null
    [ -n "$PUSHOVER_TOKEN" ] && curl -s \
        --form-string "token=$PUSHOVER_TOKEN" \
        --form-string "user=$PUSHOVER_USER" \
        --form-string "title=Blocker: $BLOCKER_TITLE" \
        --form-string "message=Task parked. Other work continues." \
        --form-string "priority=1" \
        https://api.pushover.net/1/messages.json > /dev/null 2>&1

    rm -f "$LOCK"
    "$WORKSPACE/heartbeat.sh" "blocked-parked" "$BLOCKER_TITLE (parked, queue continues)"
    exit 0
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "$LOCK"

if [ $EXIT_CODE -eq 0 ]; then
    [ -f "$TASK_FILE" ] && mv "$TASK_FILE" "$TASKS/queue/done/DONE-${TASK_SLUG}.md"
    rm -f "$TASKS/queue/.retries-${TASK_SLUG}"
    echo "[executor] Task complete: $TASK_SLUG (exit 0)" >> "$TASKS/watchdog.log"
    "$WORKSPACE/heartbeat.sh" "executor-complete" "$TASK_SLUG"
else
    # Track retries — park the task after 3 failures
    RETRY_FILE="$TASKS/queue/.retries-${TASK_SLUG}"
    RETRIES=0
    [ -f "$RETRY_FILE" ] && RETRIES=$(cat "$RETRY_FILE")
    RETRIES=$((RETRIES + 1))
    echo "$RETRIES" > "$RETRY_FILE"

    if [ "$RETRIES" -ge 3 ]; then
        echo "[executor] Task failed $RETRIES times, parking: $TASK_SLUG" >> "$TASKS/watchdog.log"
        mkdir -p "$TASKS/queue/blocked"
        [ -f "$TASK_FILE" ] && mv "$TASK_FILE" "$TASKS/queue/blocked/FAILED-${TASK_SLUG}.md"
        rm -f "$RETRY_FILE"
        "$WORKSPACE/heartbeat.sh" "executor-parked" "$TASK_SLUG (failed $RETRIES times)"

        source ~/.pushover_secrets 2>/dev/null
        [ -n "$PUSHOVER_TOKEN" ] && curl -s \
            --form-string "token=$PUSHOVER_TOKEN" \
            --form-string "user=$PUSHOVER_USER" \
            --form-string "title=Task Failed (3 retries)" \
            --form-string "message=$TASK_SLUG failed 3 times. Parked in blocked/." \
            --form-string "priority=0" \
            https://api.pushover.net/1/messages.json > /dev/null 2>&1
    else
        echo "[executor] Task failed (attempt $RETRIES/3): $TASK_SLUG (exit $EXIT_CODE)" >> "$TASKS/watchdog.log"
        "$WORKSPACE/heartbeat.sh" "executor-error" "$TASK_SLUG (attempt $RETRIES/3, exit $EXIT_CODE)"
    fi
fi
