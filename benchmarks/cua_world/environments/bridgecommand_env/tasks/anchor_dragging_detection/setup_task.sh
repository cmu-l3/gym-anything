#!/bin/bash
echo "=== Setting up Anchor Dragging Detection Task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) St Helens Anchor Drag"
BRIEFING_FILE="/home/ga/Documents/instructor_briefing.txt"

# Ensure clean state
echo "Cleaning up previous scenario artifacts..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$BRIEFING_FILE" 2>/dev/null || true

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial file system state (to ensure new files are actually created)
ls -R "$BC_DATA/Scenarios/" 2>/dev/null | grep ":" | wc -l > /tmp/initial_scenario_count.txt

# Setup window for agent (if they choose to launch BC)
# We don't launch it automatically as this is primarily a file creation task,
# but we ensure the environment is ready.
pkill -f "bridgecommand" 2>/dev/null || true

# Take initial screenshot of desktop/terminal
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="