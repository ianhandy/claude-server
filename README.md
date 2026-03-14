# claude-server

**Run Claude Code autonomously on your Mac — with task queuing, crash recovery, phone notifications, and a live dashboard.**

Drop a task file in the queue. Walk away. Claude picks it up, executes it headlessly, writes session logs, commits the work, and pings your phone when it's done or blocked.

No cloud. No Docker. Just launchd + shell scripts + Claude Code.

---

## What It Does

```
You (phone/laptop)                       Mac Server
    │                                         │
    │  drop task file ────────────────►  tasks/queue/PENDING-*.md
    │                                         │
    │                                    watchdog (every 2 min)
    │                                         │
    │                                    executor.sh
    │                                         │ runs: claude --print
    │                                         │ writes: heartbeat, session log
    │                                         │ commits + pushes
    │                                         │
    │  ◄──── Pushover notification ─────  done (or blocked)
    │                                         │
    │  open dashboard ───────────────►  localhost:3000
    │  (status, chat, resolve blockers)       │
```

### Core Features

- **Task queue** — Drop a `.md` file in `tasks/queue/`, watchdog picks it up within 2 minutes
- **Crash recovery** — Stale heartbeat = auto-restart + phone notification. 3 retries before parking.
- **Blocker system** — Claude parks a task and asks you a question via dashboard. Queue continues with other tasks.
- **Daily briefs** — 8am summary of overnight work: commits, session logs, open questions
- **Phone notifications** — Pushover for blockers, crashes, daily briefs, inbox replies
- **Web dashboard** — Real-time status, chat (via OpenRouter free models), inbox for directives
- **Session logs** — Structured reasoning logs with decisions, rationale, and keyword-indexed search
- **Inbox/Outbox** — Send messages to Claude from the dashboard, get replies in ~2 min

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  launchd (macOS)                                        │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────────┐  │
│  │ watchdog │  │  brief   │  │     dashboard         │  │
│  │ (2 min)  │  │ (8am)    │  │   (always-on:3000)    │  │
│  └────┬─────┘  └──────────┘  └───────────────────────┘  │
│       │                                                  │
│       ▼                                                  │
│  ┌──────────┐     ┌──────────────┐                      │
│  │ executor │────▶│ claude --print│                      │
│  └────┬─────┘     └──────┬───────┘                      │
│       │                  │                               │
│       ▼                  ▼                               │
│  tasks/queue/       heartbeat.json                       │
│  PENDING-*.md       session logs                         │
│                     git commits                          │
└─────────────────────────────────────────────────────────┘
         │
         ▼
   ┌──────────┐
   │ Pushover │  ← phone notifications
   └──────────┘
```

**Flow:**
1. You drop a `PENDING-*.md` task file in `tasks/queue/`
2. Watchdog (launchd, every 2 min) finds it, calls `executor.sh`
3. Executor builds a prompt from CLAUDE.md + task content, runs `claude --print`
4. Claude writes heartbeats as it works (watchdog monitors freshness)
5. On completion: task moves to `done/`, session log written, git commit
6. On blocker: task parks in `blocked/`, you get a phone notification, queue continues
7. On crash: watchdog detects stale heartbeat, clears lock, re-queues (up to 3 retries)

---

## Quickstart (5 minutes)

### Prerequisites

- macOS (uses launchd for process management)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude -p "hello"` works)
- Node.js 18+ (`brew install node`)
- Python 3 (ships with macOS)

### Install

```bash
git clone https://github.com/ianhandy/claude-server.git ~/claude-server
cd ~/claude-server
./setup.sh
```

The setup script will:
1. Create the `tasks/` directory structure
2. Install dashboard dependencies (`npm install`)
3. Install and load three launchd agents (watchdog, brief, dashboard)
4. Prompt you for optional Pushover and OpenRouter configuration

### Configure

**CLAUDE.md** — Edit this file. It's the standing instructions for your autonomous Claude instance. Replace `{{WORKSPACE}}` placeholders with your paths and customize the operating principles.

**Pushover** (optional, for phone notifications):
```bash
cat > ~/.pushover_secrets << 'EOF'
PUSHOVER_TOKEN="your-app-token"
PUSHOVER_USER="your-user-key"
EOF
```
Get credentials at [pushover.net](https://pushover.net).

**OpenRouter** (optional, for dashboard chat):
```bash
export OPENROUTER_API_KEY="your-key"  # free tier works fine
```
Get a key at [openrouter.ai](https://openrouter.ai).

### Queue Your First Task

```bash
cat > tasks/queue/PENDING-$(date +%Y%m%d%H%M)-hello-world.md << 'EOF'
---
repo: my-project
priority: normal
---
Create a simple hello world script.
Success criteria: running `node hello.js` prints "Hello from Claude Server!"
EOF
```

The watchdog picks it up within 2 minutes. Check progress at `http://localhost:3000`.

---

## Task File Format

```markdown
---
repo: my-project          # which repo to work in (relative to ~/repos/)
priority: normal           # normal or high
---

Description of what to do.
Success criteria — how to know it's done.
```

**Naming:** `PENDING-YYYYMMDDHHMM-slug.md`

Tasks process in alphabetical order (earliest timestamp first). Claude can queue its own follow-up tasks by writing new `PENDING-*.md` files.

---

## Dashboard

The dashboard runs at `http://localhost:3000` and shows:

- **Status panel** — current phase, task, heartbeat age, last brief
- **Blocker resolution** — discuss the situation with a chat assistant, then record your decision
- **Inbox** — send messages to your running Claude instance (replies in ~2 min)
- **Chat** — ask questions about recent work (powered by OpenRouter free models)

Access from any device on your network via Tailscale or port forwarding.

---

## How It Compares

| | claude-server | clawport-ui | ruflo | Agent HQ |
|---|---|---|---|---|
| **Runs unattended** | Yes | No | Partial | No |
| **Task queue** | File-based + launchd | No | API-driven | No |
| **Crash recovery** | Heartbeat watchdog | No | No | No |
| **Phone notifications** | Pushover | No | No | No |
| **Daily briefs** | 8am summary | No | No | No |
| **Session logging** | Structured + indexed | No | Partial | No |
| **Setup time** | ~5 min | ~5 min | ~30 min | ~10 min |
| **Cost** | $0 (Claude membership) | API costs | API costs | API costs |

**claude-server is for running Claude while you sleep.** Other tools are interactive wrappers — they help you use Claude at the keyboard. This one makes Claude productive while you're away from it.

---

## Directory Structure

```
claude-server/
├── CLAUDE.md              # Claude's standing instructions (customize this)
├── executor.sh            # Runs a single task via claude --print
├── watchdog.sh            # launchd agent — monitors queue + heartbeat
├── heartbeat.sh           # Called by Claude to signal liveness
├── brief.sh               # Generates and sends daily briefing
├── setup.sh               # One-time installer
├── dashboard/
│   ├── server.js          # Express server (status API, chat, inbox)
│   ├── public/index.html  # Single-page dashboard UI
│   └── package.json
├── plists/                # launchd agent templates
│   ├── com.claude-server.watchdog.plist
│   ├── com.claude-server.brief.plist
│   └── com.claude-server.dashboard.plist
└── tasks/                 # Created by setup.sh
    ├── queue/             # Drop PENDING-*.md files here
    │   ├── done/          # Completed tasks
    │   └── blocked/       # Failed/blocked tasks
    ├── inbox/             # Messages to Claude
    ├── outbox/            # Replies from Claude
    └── repos/             # Per-repo session logs + keyword indexes
```

---

## Customization

**Repos directory** — Set `REPOS_DIR` to change where the executor looks for repos (default: `~/repos/`).

**Watchdog interval** — Edit `StartInterval` in the watchdog plist (default: 120 seconds).

**Brief schedule** — Edit `StartCalendarInterval` in the brief plist (default: 8:00am).

**Session log format** — Edit the log structure in `CLAUDE.md`. Claude follows whatever format you specify.

---

## FAQ

**Does this need an Anthropic API key?**
No. It uses `claude --print` which runs through your Claude Code CLI authentication. The dashboard chat uses OpenRouter free models (also $0).

**Can I run this on Linux?**
The scripts work anywhere with zsh and python3. Replace launchd with cron or systemd for scheduling.

**What if Claude gets stuck in a loop?**
The watchdog detects stale heartbeats (5 min silence = crash). It clears the lock, re-queues the task, and notifies you. After 3 failed attempts, the task is parked in `blocked/`.

**Can Claude queue its own follow-up tasks?**
Yes. A running task can write new `PENDING-*.md` files to the queue. The watchdog picks them up after the current task finishes.

**Is my code safe?**
Claude runs with `--dangerously-skip-permissions` (required for headless execution). This means it can read/write/execute anything on your Mac. Run this on a dedicated machine or user account if that concerns you.

---

## License

MIT
