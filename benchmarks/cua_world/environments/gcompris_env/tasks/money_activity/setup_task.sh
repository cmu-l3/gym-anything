#!/bin/bash
set -e
echo "=== Setting up Money Activity Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous evidence
rm -rf "/home/ga/Documents/money_evidence"
mkdir -p "/home/ga/Documents"

# Ensure GCompris is running at the main menu
# Kill existing to ensure clean state
kill_gcompris

# Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# Ensure window is maximized for best visibility
maximize_gcompris

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is open at the main menu."
echo "Agent must navigate to Money activity, complete rounds, and save evidence."