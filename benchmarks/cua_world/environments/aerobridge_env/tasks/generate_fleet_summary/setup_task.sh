#!/bin/bash
# Setup script for generate_fleet_summary task

echo "=== Setting up generate_fleet_summary task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Ensure Aerobridge server is running (standard env state)
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Prepare the workspace
mkdir -p /home/ga/Documents
# Remove any previous report to ensure we verify a fresh creation
rm -f /home/ga/Documents/fleet_summary.txt

# 3. Record task start time for anti-gaming (file mtime check)
date +%s > /tmp/task_start_time.txt

# 4. Open a Terminal for the agent (hinting this is a CLI task)
# We also keep Firefox open as per standard state, but focus Terminal
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
    sleep 2
fi

# 5. Focus the terminal window
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="