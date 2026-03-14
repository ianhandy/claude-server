# Reddit Post Draft — r/ClaudeAI

**Title:** I built a system to run Claude Code autonomously on my Mac while I sleep — open sourced it

**Body:**

I've been running Claude Code headlessly on a Mac as an autonomous development server for the past few weeks. It processes a queue of tasks overnight, writes detailed session logs, auto-recovers from crashes, and pings my phone when it's blocked or done.

Today I cleaned it up and open-sourced it: [**claude-server**](https://github.com/ianhandy/claude-server)

### How it works

You drop a markdown file in a `tasks/queue/` folder describing what you want done. A launchd watchdog (runs every 2 min) picks it up and runs `claude --print` with the task prompt. Claude writes heartbeats as it works — if the heartbeat goes stale for 5 minutes, the watchdog assumes a crash, clears the lock, and re-queues the task (up to 3 retries).

When Claude hits a decision it can't make alone, it writes a BLOCKER.md file, parks the task, notifies your phone, and moves on to the next task in the queue. You resolve the blocker from a web dashboard.

### What's included

- **Task queue** — file-based, FIFO, with retry logic
- **Watchdog** — crash detection, auto-recovery, blocker handling
- **Heartbeat** — liveness signal + auto git sync
- **Dashboard** — web UI with status, chat (OpenRouter free models), inbox
- **Daily briefs** — 8am summary sent to your phone via Pushover
- **Session logs** — structured reasoning logs with keyword indexing
- **Setup script** — `./setup.sh` gets you running in ~5 minutes

### What makes this different from other tools

Most Claude Code tools I've seen (clawport-ui, Agent HQ, etc.) are interactive wrappers — they make Claude easier to use while you're at the keyboard. This is designed for the opposite: Claude working while you're away from the keyboard.

No API key needed (uses `claude --print` through your Claude Code CLI auth). No Docker. No cloud. Just launchd + shell scripts.

### Cost

$0 beyond your Claude membership. Dashboard chat uses OpenRouter free models.

---

**GitHub:** https://github.com/ianhandy/claude-server

Happy to answer questions about the architecture or how I've been using it.
