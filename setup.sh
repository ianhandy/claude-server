#!/bin/zsh
# setup.sh — Install claude-server on macOS.
# Run this once after cloning. It will:
#   1. Create the tasks/ directory structure
#   2. Install dashboard dependencies
#   3. Install and load launchd agents
#   4. Optionally configure Pushover notifications

set -e

WORKSPACE="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
NODE_PATH=$(which node 2>/dev/null || echo "/opt/homebrew/bin/node")
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

echo "Claude Server Setup"
echo "==================="
echo ""
echo "Workspace: $WORKSPACE"
echo "Node:      $NODE_PATH"
echo ""

# ── Preflight checks ────────────────────────────────────────────────────────
check() {
    command -v "$1" > /dev/null 2>&1 || { echo "ERROR: $1 not found. Install it first."; exit 1; }
}

check node
check npm
check python3
check git

# Check for Claude Code CLI
if ! command -v claude > /dev/null 2>&1; then
    echo "WARNING: 'claude' CLI not found."
    echo "Install it: npm install -g @anthropic-ai/claude-code"
    echo "The server will not be able to execute tasks without it."
    echo ""
fi

# ── Create directory structure ───────────────────────────────────────────────
echo "Creating directory structure..."
mkdir -p "$WORKSPACE/tasks/"{queue/{done,blocked},inbox,outbox,repos,briefs,chats}
echo "  tasks/ directories created."

# ── Make scripts executable ──────────────────────────────────────────────────
chmod +x "$WORKSPACE"/{executor,watchdog,heartbeat,brief}.sh
echo "  Scripts marked executable."

# ── Install dashboard dependencies ──────────────────────────────────────────
echo "Installing dashboard dependencies..."
cd "$WORKSPACE/dashboard" && npm install --silent
echo "  Dashboard ready."

# ── Pushover setup (optional) ───────────────────────────────────────────────
if [ ! -f "$HOME/.pushover_secrets" ]; then
    echo ""
    echo "Pushover notifications (optional):"
    echo "  To get phone notifications for blockers and daily briefs,"
    echo "  create ~/.pushover_secrets with:"
    echo ""
    echo '  PUSHOVER_TOKEN="your-app-token"'
    echo '  PUSHOVER_USER="your-user-key"'
    echo ""
    echo "  Get these at https://pushover.net"
    echo "  Skipping for now — notifications will be disabled."
else
    echo "  Pushover credentials found."
fi

# ── OpenRouter setup (optional) ─────────────────────────────────────────────
echo ""
echo "Dashboard chat uses OpenRouter (free models by default)."
echo "  Get a free API key at https://openrouter.ai"
echo "  Set it: export OPENROUTER_API_KEY='your-key'"
OPENROUTER_KEY="${OPENROUTER_API_KEY:-}"

# ── Install launchd agents ──────────────────────────────────────────────────
echo ""
echo "Installing launchd agents..."
mkdir -p "$LAUNCH_AGENTS"

install_plist() {
    local src="$1" label="$2"
    local dest="$LAUNCH_AGENTS/${label}.plist"

    # Replace template variables
    sed \
        -e "s|{{WORKSPACE}}|$WORKSPACE|g" \
        -e "s|{{HOME}}|$HOME_DIR|g" \
        -e "s|{{NODE_PATH}}|$NODE_PATH|g" \
        -e "s|{{OPENROUTER_API_KEY}}|${OPENROUTER_KEY}|g" \
        "$src" > "$dest"

    # Unload if already loaded, then load
    launchctl unload "$dest" 2>/dev/null || true
    launchctl load "$dest"
    echo "  Loaded: $label"
}

install_plist "$WORKSPACE/plists/com.claude-server.watchdog.plist" "com.claude-server.watchdog"
install_plist "$WORKSPACE/plists/com.claude-server.brief.plist" "com.claude-server.brief"
install_plist "$WORKSPACE/plists/com.claude-server.dashboard.plist" "com.claude-server.dashboard"

# ── Git init (if not already a repo) ────────────────────────────────────────
cd "$WORKSPACE"
if [ ! -d ".git" ]; then
    git init
    git add -A
    git commit -m "Initial commit — claude-server setup"
    echo "  Git repo initialized."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "Setup complete!"
echo ""
echo "Dashboard:  http://localhost:3000"
echo "Watchdog:   Running (checks every 2 min)"
echo "Briefing:   Daily at 8am (run ./brief.sh manually anytime)"
echo ""
echo "To queue your first task:"
echo '  cat > tasks/queue/PENDING-$(date +%Y%m%d%H%M)-my-task.md << EOF'
echo '  ---'
echo '  repo: my-project'
echo '  priority: normal'
echo '  ---'
echo '  What to do and success criteria.'
echo '  EOF'
echo ""
echo "The watchdog will pick it up within 2 minutes."
