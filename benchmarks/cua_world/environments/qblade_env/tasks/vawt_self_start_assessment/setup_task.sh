#!/bin/bash
set -e
echo "=== Setting up VAWT Self-Start Assessment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# Clean up any previous task artifacts to ensure a fresh start
rm -f /home/ga/Documents/projects/vawt_selfstart.wpa
rm -f /home/ga/Documents/projects/vawt_selfstart_report.txt
rm -f /tmp/task_result.json

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize the window using wmctrl if available (ensures visibility for VLM)
if command -v wmctrl &> /dev/null; then
    echo "Maximizing QBlade window..."
    DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="