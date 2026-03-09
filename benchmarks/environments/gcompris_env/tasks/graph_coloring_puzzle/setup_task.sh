#!/bin/bash
set -e
echo "=== Setting up Graph Coloring Puzzle Task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous state
# Kill running instances
kill_gcompris

# Remove previous results
rm -f /home/ga/graph_solved.png
rm -f /tmp/task_result.json

# Reset GCompris progress to ensure Level 1
# GCompris-qt stores progress in sqlite database in .local/share
echo "Resetting GCompris progress..."
rm -rf /home/ga/.local/share/GCompris-qt
rm -rf /home/ga/.local/share/GCompris
mkdir -p /home/ga/.local/share/GCompris-qt

# 2. Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# 3. Configure Window
# Wait for window to be ready
sleep 5
maximize_gcompris

# 4. Optional: Pre-navigate to the Logic category to reduce search space?
# The prompt says "Starting State: GCompris is launched and displaying the main menu."
# So we will leave it at the main menu.
# However, we make sure it's focused.
DISPLAY=:1 wmctrl -a "GCompris" 2>/dev/null || true

# 5. Capture initial state
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="