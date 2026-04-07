#!/bin/bash
set -e
echo "=== Setting up VTS Traffic Density Exercise ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Target paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Solent VTS Traffic Density"
DOCS_DIR="/home/ga/Documents"
LOG_FILE="$DOCS_DIR/vts_watch_handover_log.txt"

# 1. Clean State: Remove any existing files from previous runs
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

if [ -f "$LOG_FILE" ]; then
    echo "Removing existing log file..."
    rm -f "$LOG_FILE"
fi

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Verify Environment
# Ensure Solent world exists (critical for task)
if [ ! -d "/opt/bridgecommand/World/Solent" ] && ! ls /opt/bridgecommand/World/ 2>/dev/null | grep -qi "solent"; then
    echo "WARNING: Solent world not found in standard location. Checking installation..."
    # Proceeding anyway as it might be a custom install, but logging warning
fi

# 3. Setup Agent View
# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null && ! pgrep -f "xterm" > /dev/null; then
    echo "Opening terminal for agent..."
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30+50+50 -title 'Task Terminal' &"
    sleep 2
fi

# 4. Capture Initial State
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent must create scenario at: $SCENARIO_DIR"
echo "Agent must create log at: $LOG_FILE"