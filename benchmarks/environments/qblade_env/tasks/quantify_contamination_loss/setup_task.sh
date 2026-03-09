#!/bin/bash
set -e
echo "=== Setting up Quantify Contamination Loss Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/projects/contamination_study.wpa
rm -f /home/ga/Documents/contamination_report.txt
rm -f /tmp/task_result.json

# 3. Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# 4. Launch QBlade
# We use the shared utility which handles display, user, and background execution
echo "Launching QBlade..."
launch_qblade

# 5. Wait for window to appear
wait_for_qblade 30

# 6. Maximize window (Critical for VLM/Agent visibility)
# Retry a few times as QBlade might take a moment to be responsive
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null; then
        echo "Window maximized"
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="