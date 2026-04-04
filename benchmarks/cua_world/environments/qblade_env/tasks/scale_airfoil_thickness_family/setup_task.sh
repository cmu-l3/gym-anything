#!/bin/bash
set -e
echo "=== Setting up scale_airfoil_thickness_family task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts to ensure a fresh start
echo "Cleaning up previous data..."
rm -rf /home/ga/Documents/airfoils/family
rm -f /home/ga/Documents/projects/airfoil_family_scaling.wpa
rm -f /tmp/task_result.json

# Create the target directory so the agent doesn't struggle with "directory not found" errors
# (The task is about scaling, not bash mkdir commands)
mkdir -p /home/ga/Documents/airfoils/family
chown -R ga:ga /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents/projects

# 2. Launch QBlade
echo "Launching QBlade..."
if ! is_qblade_running > /dev/null; then
    launch_qblade
    
    # Wait for window
    wait_for_qblade 30
fi

# 3. Ensure window is maximized and focused
echo "Configuring window..."
QBLADE_WIN=$(DISPLAY=:1 wmctrl -l | grep -i "QBlade" | head -1 | awk '{print $1}')
if [ -n "$QBLADE_WIN" ]; then
    DISPLAY=:1 wmctrl -i -r "$QBLADE_WIN" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$QBLADE_WIN"
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="