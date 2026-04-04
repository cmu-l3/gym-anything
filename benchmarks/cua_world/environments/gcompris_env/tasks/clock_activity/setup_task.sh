#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Clock Activity Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous artifacts
rm -f /tmp/clock_before.png
rm -f /tmp/clock_after.png
rm -f /tmp/task_result.json
rm -f /tmp/task_initial.png
rm -f /tmp/task_final.png

# Kill any existing GCompris instance
kill_gcompris
sleep 2

# Launch GCompris at main menu
launch_gcompris

# Maximize window for full visibility
maximize_gcompris

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state (main menu) for comparison
take_screenshot /tmp/task_initial.png

echo "Initial state screenshot saved to /tmp/task_initial.png"
echo "=== Clock Activity Task setup complete ==="