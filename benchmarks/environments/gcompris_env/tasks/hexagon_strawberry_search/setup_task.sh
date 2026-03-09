#!/bin/bash
set -e
echo "=== Setting up Hexagon Strawberry Search Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/strawberry_found.png
rm -f /tmp/task_result.json

# Ensure GCompris is running and in a clean state
kill_gcompris

# Launch GCompris at the main menu
# We launch as the 'ga' user to ensure permissions are correct for the agent
echo "Launching GCompris..."
launch_gcompris

# Maximize the window to ensure the agent can see everything clearly
maximize_gcompris

# Dismiss any potential startup dialogs (though config should handle this)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take an initial screenshot to prove starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "GCompris is running on the main menu."
echo "Agent needs to: Navigate to Puzzles -> Hexagon -> Find Strawberry -> Screenshot."