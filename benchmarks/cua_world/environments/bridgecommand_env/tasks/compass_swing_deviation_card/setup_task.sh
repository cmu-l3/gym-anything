#!/bin/bash
set -e
echo "=== Setting up Compass Swing Deviation Card Task ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Solent Compass Swing"
DOCS_DIR="/home/ga/Documents"
DEVIATION_FILE="$DOCS_DIR/compass_deviation_card.txt"
GUIDE_FILE="$DOCS_DIR/compass_swing_instructor_guide.txt"

# 1. Clean up any previous run artifacts (Anti-gaming: ensure clean state)
echo "Cleaning up previous artifacts..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DEVIATION_FILE" 2>/dev/null || true
rm -f "$GUIDE_FILE" 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Record start time (Anti-gaming: files must be created AFTER this)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Ensure Bridge Command is ready (not running initially, but installed)
BC_BIN="/opt/bridgecommand/bridgecommand"
if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    # Try to find it if moved
    BC_BIN=$(which bridgecommand || echo "")
    if [ -z "$BC_BIN" ]; then
        echo "CRITICAL: Bridge Command not installed."
        exit 1
    fi
fi

# 4. Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30+100+100 &"
    sleep 2
fi

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="