#!/bin/bash
set -e
echo "=== Setting up optimize_blade_schmitz task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous attempts
rm -f /home/ga/Documents/projects/optimized_rotor.wpa
rm -f /home/ga/Documents/projects/results.txt
rm -f /tmp/task_result.json

# 3. Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# 4. Launch QBlade (fresh session)
echo "Launching QBlade..."
launch_qblade
sleep 5

# 5. Wait for window and maximize
wait_for_qblade 30
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="