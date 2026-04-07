#!/bin/bash
echo "=== Setting up TSS Violation Intercept task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/z) TSS Rogue Intercept"
BRIEFING_FILE="/home/ga/Documents/intercept_briefing.txt"

# Ensure BC is installed
if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    exit 1
fi

# Clean state: Remove the specific scenario if it exists from previous runs
if [ -d "$SCENARIO_DIR" ]; then
    echo "Cleaning up existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Clean state: Remove briefing file
if [ -f "$BRIEFING_FILE" ]; then
    rm -f "$BRIEFING_FILE"
fi

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Reset bc5.ini to known state to avoid side effects from other tasks
mkdir -p "/home/ga/.config/Bridge Command"
cp /workspace/config/bc5.ini "/home/ga/.config/Bridge Command/bc5.ini" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config"

# Launch Bridge Command (warmup/verify) then close, or just ensure it's closed
# We want the agent to do file creation, so BC doesn't strictly need to be running, 
# but we'll ensure the environment is ready.
pkill -f "bridgecommand" 2>/dev/null || true

# Take initial screenshot of the desktop/terminal
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="