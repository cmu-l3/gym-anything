#!/bin/bash
set -e
echo "=== Setting up Chronos Sequence task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state by killing existing instances
kill_gcompris

# Launch GCompris at the main menu
# The utility handles launching as 'ga' user and waiting for window
launch_gcompris

# Wait for UI to stabilize
sleep 5

# Maximize the window for better VLM visibility
maximize_gcompris

# Dismiss any potential startup dialogs/popups
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

# Verify setup
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Task setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent must navigate to Discovery/History -> Chronos -> Sort items."