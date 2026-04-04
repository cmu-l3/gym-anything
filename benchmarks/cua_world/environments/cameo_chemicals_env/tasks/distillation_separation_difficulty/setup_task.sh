#!/bin/bash
# setup_task.sh - Pre-task hook for distillation_separation_difficulty
set -e

echo "=== Setting up Distillation Separation Difficulty Task ==="

# Source shared utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/distillation_schedule.txt 2>/dev/null || true
# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Ensure Firefox is running and navigated to CAMEO Chemicals
echo "Launching Firefox..."
kill_firefox "ga"
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

# 5. Verify setup
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Task Setup Complete ==="