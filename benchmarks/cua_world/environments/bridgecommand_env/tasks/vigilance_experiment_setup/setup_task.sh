#!/bin/bash
echo "=== Setting up Vigilance Experiment Task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/Exp) Vigilance Study 4H"

# Ensure clean state: Remove the specific scenario directory if it exists
# This forces the agent to create it from scratch
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory for clean start..."
    rm -rf "$SCENARIO_DIR"
fi

# Remove briefing file if exists
rm -f "/home/ga/Documents/experiment_briefing.txt" 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Bridge Command is ready (not necessarily running, but installed)
if [ ! -x "$BC_DATA/bridgecommand" ]; then
    echo "ERROR: Bridge Command binary not found"
    exit 1
fi

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Target scenario directory: $SCENARIO_DIR"