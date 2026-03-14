# claude-server

Run Claude Code autonomously on your Mac. Task queue, watchdog, phone notifications, web dashboard — all powered by launchd.

**claude-server** is a template for turning a Mac into an autonomous Claude Code workstation. Drop a task file in the queue, walk away. Claude picks it up, executes it headlessly, commits the work, and pings your phone when it's done or blocked.

No cloud. No Docker. Just launchd + shell scripts + Claude Code.

---

## What It Does

```
You (phone)                          Mac Server
    │                                     │
    │  drop task file ──────────────►  tasks/queue/PENDING-*.md
    │                                     │
    │                                  watchdog (every 2 min)
    │                                     │
    │                                  executor.sh
    │                                     │ runs: claude --print
    │                                     │ writes: heartbeat, session log
    │                                     │ commits + pushes
    │                                     │
    │  ◄──── Pushover notification ───  done (or blocked)
    │                                     │
    │  open dashboard ─────────────►  localhost:3000
    │  (chat, status, briefs)             │
```

### Core Components

| File | Purpose |
|------|---------|
| `watchdog.sh` | Runs every 2 min via launchd. Picks up pending tasks, detects crashes, handles blockers. |
| `executor.sh` | Runs a single task headlessly via `claude --print`. Manages locks, heartbeats, retries. |
| `heartbeat.sh` | Writes `tasks/heartbeat.json` + auto-syncs to git. Watchdog uses this to detect crashes. |
| `brief.sh` | Generates a daily briefing and sends it via Pushover. Runs at 8am. |
| `dashboard/` | Node.js web dashboard — status, chat (via OpenRouter free models), inbox for directives. |
| `CLAUDE.md` | Standing orders for the autonomous Claude instance. Customize this. |

### Features

- **Task queue** — drop a `.md` file in `tasks/queue/`, watchdog executes it
- **Crash recovery** — stale heartbeat = auto-restart + phone notification
- **Blocker system** — Claude can park a task and ask you a question via the dashboard
- **Daily briefs** — morning summary of what happened overnight
- **Web dashboard** — real-time status, chat with a briefing assistant, send directives
- **Inbox/Outbox** — send messages to Claude from the dashboard, get replies
- **Session logs** — every task produces a structured reasoning log for audit
- **Auto-retry** — failed tasks retry 3x before parking in `blocked/`

---

## Quickstart (5 minutes)

### Prerequisites

- macOS (uses launchd)
- [Claude Code](https://claude.com/code) installed and authenticated (`claude -p "hello"` works)
- Node.js 18+ (`brew install node`)
- [Pushover](https://pushover.net/) account (for phone notifications) — optional but recommended

### 1. Clone and configure

```bash
git clone https://github.com/ianhandy/claude-server.git ~/claude-server
cd ~/claude-server
```

Edit `CLAUDE.md` — this is the system prompt for your autonomous Claude. Customize the identity, workspace paths, and operating principles.

### 2. Set up Pushover (optional)

Create `~/.pushover_secrets`:

```bash
PUSHOVER_TOKEN=your_app_token
PUSHOVER_USER=your_user_key
```

### 3. Install dashboard dependencies

```bash
cd dashboard && npm install && cd ..
```

For chat functionality, get a free [OpenRouter](https://openrouter.ai/) API key and add it to the watchdog plist (see step 4).

### 4. Install launchd agents

Edit the plist files in `plists/` — update paths to match your install location.

```bash
# Copy plists to LaunchAgents
cp plists/*.plist ~/Library/LaunchAgents/

# Load them
launchctl load ~/Library/LaunchAgents/com.claude-server.watchdog.plist
launchctl load ~/Library/LaunchAgents/com.claude-server.dashboard.plist
launchctl load ~/Library/LaunchAgents/com.claude-server.brief.plist
```

### 5. Queue your first task

```bash
cat > tasks/queue/PENDING-202603150900-hello-world.md << 'EOF'
---
repo: uncategorized
priority: normal
---

Say hello. Write a file called `hello.txt` in the workspace root with today's date and a haiku about autonomous AI.

Success criteria: hello.txt exists with content.
EOF
```

The watchdog will pick it up within 2 minutes.

### 6. Open the dashboard

Visit `http://localhost:3000` — you'll see the heartbeat, task status, and chat panel.

---

## Task File Format

```markdown
---
repo: my-project        # which repo to work in (under ~/Programming/repos/)
priority: normal         # normal or high
---

Description of what to do.
Success criteria.
```

Drop it in `tasks/queue/` with the naming convention: `PENDING-YYYYMMDDHHMM-slug.md`

---

## Architecture

```
claude-server/
├── CLAUDE.md           — standing orders (system prompt for autonomous Claude)
├── executor.sh         — runs one task via claude --print
├── watchdog.sh         — picks up tasks, handles crashes (launchd, every 2 min)
├── heartbeat.sh        — status beacon + git sync
├── brief.sh            — daily summary generator + Pushover push
├── dashboard/
│   ├── server.js       — Express server (status API, chat via OpenRouter, inbox)
│   └── public/
│       └── index.html  — web UI
├── plists/             — launchd agent templates
└── tasks/
    ├── heartbeat.json  — current status
    ├── queue/          — PENDING-*.md tasks → done/ when complete
    │   ├── done/
    │   └── blocked/    — tasks that failed 3x or hit a blocker
    ├── inbox/          — messages from you → Claude reads these
    ├── outbox/         — Claude's replies
    ├── chats/          — dashboard chat transcripts (auto-saved)
    ├── briefs/         — archived daily briefs
    └── repos/          — session logs per repo
        └── {repo}/
            ├── INDEX.md
            └── sessions/
```

---

## How It Compares

| | claude-server | [clawport-ui](https://github.com/JohnRiceML/clawport-ui) | [ruflo](https://github.com/ruvnet/ruflo) | [claude-ws](https://github.com/Claude-Workspace/claude-ws) |
|---|---|---|---|---|
| **Runs where** | Your Mac | Cloud/Docker | Cloud | Local/Cloud |
| **Execution** | Headless `claude --print` | IDE agent teams | Swarm orchestration | REST+SSE backend |
| **Task queue** | File-based, launchd | No | API-driven | Kanban board |
| **Phone notifications** | Pushover | No | No | No |
| **Crash recovery** | Heartbeat watchdog | No | No | No |
| **Daily briefs** | Yes (8am) | No | No | No |
| **Dependencies** | Claude Code + Node.js | Docker + cloud | Docker + cloud | Docker |
| **Setup time** | 5 min | 15+ min | 30+ min | 15+ min |
| **Cost** | $0 (Claude membership) | API costs | API costs | API costs |

---

## FAQ

**Q: Does this need an Anthropic API key?**
A: No. It uses `claude --print` which runs through your Claude Code membership. The dashboard chat uses OpenRouter free models (also $0).

**Q: Can I run this on Linux?**
A: The core scripts work anywhere, but the scheduling uses launchd (macOS). Replace with cron or systemd on Linux.

**Q: What if Claude gets stuck?**
A: The watchdog detects stale heartbeats (5 min silence = crash). It clears the lock, re-queues the task, and pings your phone.

**Q: Can Claude queue its own follow-up tasks?**
A: Yes. A running task can write a new `PENDING-*.md` file to the queue. The watchdog picks it up after the current task finishes.

---

## License

MIT
