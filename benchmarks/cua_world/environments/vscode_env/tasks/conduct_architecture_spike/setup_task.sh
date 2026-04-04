#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Conduct Architecture Spike Task ==="

WORKSPACE_DIR="/home/ga/workspace"
USER="ga"

# Clean workspace completely
echo "Cleaning workspace..."
sudo -u "$USER" rm -rf "$WORKSPACE_DIR"/*
sudo -u "$USER" rm -rf "$WORKSPACE_DIR"/.vscode
sudo -u "$USER" rm -rf "$WORKSPACE_DIR"/.git

# Initialize Git repository
echo "Initializing Git repository..."
cd "$WORKSPACE_DIR"
sudo -u "$USER" git init
sudo -u "$USER" git config user.email "engineer@example.com"
sudo -u "$USER" git config user.name "Spike Engineer"

# Ensure Redis is installed (should be from environment setup)
if ! command -v redis-server &> /dev/null; then
    echo "Installing Redis..."
    apt-get update -qq
    apt-get install -y redis-server redis-tools
fi

# Stop Redis server (not needed for spike, just installation check)
sudo systemctl stop redis-server 2>/dev/null || true
sudo systemctl disable redis-server 2>/dev/null || true

# Ensure Python 3 and pip are available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 not found"
    exit 1
fi

# Install redis-py system-wide for reference (agent will add to requirements.txt)
pip3 install redis --quiet 2>/dev/null || true

# Create Python virtual environment in workspace
echo "Creating Python virtual environment..."
sudo -u "$USER" python3 -m venv "$WORKSPACE_DIR/.venv" 2>/dev/null || true

# Open VSCode to workspace
echo "Opening VSCode..."
if pgrep -f "code.*$WORKSPACE_DIR" > /dev/null; then
    echo "VSCode already running with workspace"
else
    su - "$USER" -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
    wait_for_vscode 20
fi

wait_for_window "Visual Studio Code" 30

# Click center to focus desktop
su - "$USER" -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Architecture Spike Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "You need to create an architecture spike workspace comparing Redis vs. in-memory session storage."
echo ""
echo "📁 Required Structure:"
echo "  session_spike/"
echo "    ├── redis_approach.py       (Redis session storage class)"
echo "    ├── memory_approach.py      (In-memory session storage class)"
echo "    ├── benchmark.py            (Benchmark comparing both)"
echo "    ├── requirements.txt        (List 'redis' dependency)"
echo "    └── FINDINGS.md             (Documentation)"
echo "  .vscode/"
echo "    ├── settings.json           (Python interpreter config)"
echo "    └── launch.json             (Debug config for benchmark)"
echo ""
echo "🎯 Requirements:"
echo "  1. Both storage classes must implement set(key, value) and get(key) methods"
echo "  2. benchmark.py must import both approaches and include timing logic"
echo "  3. VSCode configs must specify Python interpreter and debug configuration"
echo "  4. FINDINGS.md must have sections: Problem, Approaches, Results, Trade-offs"
echo "  5. Make at least 2 Git commits tracking your spike progress"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Git initialized: Yes"
echo "Redis installed: Yes (but not running - this is exploratory code)"