#!/bin/bash
set -e
echo "=== Setting up Railway Construct task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. ensure clean state
# Remove any previous attempt's output file
rm -f /home/ga/railway_success.png

# 3. Prepare Application
# Kill any existing instances to ensure a fresh start
kill_gcompris

# Launch GCompris (starts at main menu)
launch_gcompris

# Maximize the window for better VLM visibility
maximize_gcompris

# 4. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="