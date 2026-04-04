#!/bin/bash
echo "=== Setting up design_high_solidity_rotor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts to ensure a fresh start
rm -f /home/ga/Documents/wind_pump_performance.txt
rm -f /home/ga/Documents/design_summary.txt
rm -f /home/ga/Documents/projects/wind_pump.wpa
rm -f /tmp/task_result.json
rm -f /tmp/task_start_time.txt

# 2. Create required directories
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch QBlade
echo "Launching QBlade..."
launch_qblade

# 5. Wait for QBlade window
wait_for_qblade 30

# 6. Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="