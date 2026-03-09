#!/bin/bash
echo "=== Setting up Crane Puzzle Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous completion files
rm -f /home/ga/crane_completion.png 2>/dev/null

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris (starts at Main Menu)
# We do not navigate to the specific activity; the agent must find it.
echo "Launching GCompris..."
launch_gcompris

# Ensure window is maximized for consistent VLM analysis
maximize_gcompris

# Dismiss any potential "profile" or "welcome" dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot of the starting state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "GCompris is open at the Main Menu."
echo "Agent instructions: Find 'Puzzle' category -> Open 'Crane' activity -> Complete Level 1 & 2 -> Screenshot to /home/ga/crane_completion.png"