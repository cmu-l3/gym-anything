#!/bin/bash
set -e
echo "=== Setting up Align 4 Winner task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state by killing existing instances
kill_gcompris

# Clear any previous results
rm -f /home/ga/Documents/align4_win.png
rm -f /tmp/gcompris_db_dump.txt

# Launch GCompris
# We launch it at the main menu so the agent has to navigate
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris launched. Agent must navigate to Strategy > Align 4 and win."