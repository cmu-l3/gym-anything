#!/bin/bash
set -e
echo "=== Setting up Determine Optimal RPM task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /home/ga/Documents/projects/rpm_study.wpa
rm -f /home/ga/Documents/projects/optimal_rpm_report.txt
rm -f /tmp/task_result.json

# 3. Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# 4. Launch QBlade
echo "Launching QBlade..."
launch_qblade

# 5. Wait for window and maximize
if wait_for_qblade 60; then
    echo "QBlade started successfully"
    sleep 2
    # Find window ID and maximize
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "QBlade" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -ia "$WID"
    fi
else
    echo "ERROR: QBlade failed to start"
    exit 1
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="