#!/bin/zsh
# watchdog.sh — runs every 2 minutes via launchd.
# Checks for pending tasks and runs them headlessly via executor.sh.
# Also handles stale/crashed tasks and respects scheduled restart times.

WORKSPACE="$(dirname "$(realpath "$0")")"
TASKS="$WORKSPACE/tasks"
QUEUE="$TASKS/queue"
HEARTBEAT="$TASKS/heartbeat.json"
LOCK="$TASKS/ACTIVE_TASK"
LOG="$TASKS/watchdog.log"
MAX_SILENCE=300  # 5 min without heartbeat = crashed

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ── Heartbeat freshness ───────────────────────────────────────────────────────
heartbeat_age() {
    [ -f "$HEARTBEAT" ] || { echo 99999; return; }
    python3 -c "
import json, time
try:
    d = json.load(open('$HEARTBEAT'))
    print(int(time.time()) - int(d.get('timestamp', 0)))
except:
    print(99999)
"
}

heartbeat_fresh() {
    [ "$(heartbeat_age)" -lt "$MAX_SILENCE" ]
}

# ── Scheduled restart check ───────────────────────────────────────────────────
restart_scheduled_future() {
    [ -f "$HEARTBEAT" ] || return 1
    local scheduled
    scheduled=$(python3 -c "
import json
try:
    print(json.load(open('$HEARTBEAT')).get('scheduled_restart',''))
except:
    print('')
" 2>/dev/null)
    [ -z "$scheduled" ] && return 1
    local now_epoch restart_epoch
    now_epoch=$(date +%s)
    restart_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$scheduled" "+%s" 2>/dev/null) || return 1
    [ "$now_epoch" -lt "$restart_epoch" ]
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    # Respect scheduled restart windows (e.g. rate limit cooldown)
    if restart_scheduled_future; then
        scheduled=$(python3 -c "import json; print(json.load(open('$HEARTBEAT')).get('scheduled_restart',''))" 2>/dev/null)
        log "Scheduled restart at $scheduled — waiting."
        exit 0
    fi

    # ── Active task check ─────────────────────────────────────────────────────
    if [ -f "$LOCK" ]; then
        if heartbeat_fresh; then
            exit 0
        else
            crashed_task=$(cat "$LOCK")
            log "CRASH DETECTED: $crashed_task — heartbeat stale. Clearing lock."
            rm -f "$LOCK"

            crashed_file=$(find "$QUEUE" -name "*${crashed_task}*" 2>/dev/null | head -1)
            if [ -n "$crashed_file" ]; then
                log "Re-queuing crashed task: $crashed_file"
            fi

            # Notify via Telegram (if configured)
            python3 - <<PYEOF
import json, os, re, urllib.request
try:
    token_env = os.path.expanduser('~/.claude/channels/telegram/.env')
    cfg_path  = os.path.expanduser('~/Programming/workspace/tasks/telegram-config.json')
    token  = re.search(r'TELEGRAM_BOT_TOKEN=(\S+)', open(token_env).read()).group(1)
    cfg    = json.load(open(cfg_path))
    payload = {'chat_id': cfg['chatId'], 'text': '*Task Crashed*\nTask $crashed_task crashed (stale heartbeat). Re-queued.', 'parse_mode': 'Markdown'}
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{token}/sendMessage',
        data=json.dumps(payload).encode(),
        headers={'Content-Type': 'application/json'},
        method='POST')
    urllib.request.urlopen(req, timeout=5)
except:
    pass
PYEOF
        fi
    fi

    # ── Blocker response check — re-queue parked task if operator responded ──
    if [ -f "$TASKS/BLOCKER.md" ] && [ -f "$TASKS/BLOCKER_RESPONSE.md" ]; then
        log "Blocker response received. Re-queuing parked task."

        PARKED=$(grep '^PARKED_TASK=' "$TASKS/BLOCKER.md" | cut -d= -f2)
        if [ -n "$PARKED" ] && [ -f "$PARKED" ]; then
            RESPONSE=$(cat "$TASKS/BLOCKER_RESPONSE.md")
            printf "\n\n## Operator's Decision (from blocker resolution)\n%s\n" "$RESPONSE" >> "$PARKED"
            SLUG=$(basename "$PARKED" | sed 's/^BLOCKED-//')
            mv "$PARKED" "$QUEUE/PENDING-${SLUG}"
            log "Re-queued: PENDING-${SLUG}"
        fi

        rm -f "$TASKS/BLOCKER.md" "$TASKS/BLOCKER_RESPONSE.md"
    fi

    # ── Inbox check — lightweight messages from operator ──────────────────────
    INBOX="$TASKS/inbox"
    OUTBOX="$TASKS/outbox"
    next_msg=$(find "$INBOX" -maxdepth 1 -name "*.md" 2>/dev/null | sort | head -1)
    if [ -n "$next_msg" ]; then
        MSG_NAME=$(basename "$next_msg" .md)
        MSG_CONTENT=$(cat "$next_msg")
        log "Inbox message: $MSG_NAME"

        REPLY=$(claude --dangerously-skip-permissions \
            --add-dir "$TASKS" \
            -p "You are a server assistant. Answer this question concisely using your knowledge of the workspace. Read files if needed.

Context: workspace is at $WORKSPACE. Tasks, logs, and ideas are in $TASKS.

Message:
$MSG_CONTENT" 2>&1)

        echo "$REPLY" > "$OUTBOX/${MSG_NAME}-reply.md"
        mv "$next_msg" "$OUTBOX/${MSG_NAME}-original.md"
        log "Inbox replied: $MSG_NAME"

        # Notify via Telegram (if configured)
        python3 - <<PYEOF
import json, os, re, urllib.request
try:
    token_env = os.path.expanduser('~/.claude/channels/telegram/.env')
    cfg_path  = os.path.expanduser('~/Programming/workspace/tasks/telegram-config.json')
    token  = re.search(r'TELEGRAM_BOT_TOKEN=(\S+)', open(token_env).read()).group(1)
    cfg    = json.load(open(cfg_path))
    preview = open('$OUTBOX/${MSG_NAME}-reply.md').read(300)
    payload = {'chat_id': cfg['chatId'], 'text': f'*Reply: $MSG_NAME*\n{preview}', 'parse_mode': 'Markdown'}
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{token}/sendMessage',
        data=json.dumps(payload).encode(),
        headers={'Content-Type': 'application/json'},
        method='POST')
    urllib.request.urlopen(req, timeout=5)
except:
    pass
PYEOF
    fi

    # ── Task queue check ──────────────────────────────────────────────────────
    next_task=$(find "$QUEUE" -maxdepth 1 -name "PENDING-*.md" | sort | head -1)

    if [ -n "$next_task" ]; then
        log "Starting task: $(basename $next_task)"
        "$WORKSPACE/executor.sh" "$next_task" &
        exit 0
    fi

    # ── Truly idle — nothing to do ───────────────────────────────────────────
    exit 0
}

main
