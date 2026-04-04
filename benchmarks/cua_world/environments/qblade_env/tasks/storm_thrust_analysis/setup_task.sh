#!/bin/bash
set -e
echo "=== Setting up Storm Thrust Analysis task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Clean up any previous runs
rm -f /home/ga/Documents/projects/storm_analysis.wpa
rm -f /home/ga/Documents/projects/storm_report.txt

# Start QBlade
echo "Starting QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# Wait for window to appear
wait_for_qblade 30

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="