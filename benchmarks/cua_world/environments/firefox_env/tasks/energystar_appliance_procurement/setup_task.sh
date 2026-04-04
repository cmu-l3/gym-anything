#!/bin/bash
# setup_task.sh - Pre-task hook for energystar_appliance_procurement

set -e
echo "=== Setting up Energy Star Procurement Task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts to ensure clean state
rm -f /home/ga/Documents/fridge_selection.json 2>/dev/null || true
# Clean downloads (be careful not to delete system files, but task-specific ones)
rm -f /home/ga/Downloads/*.xlsx 2>/dev/null || true
rm -f /home/ga/Downloads/*.csv 2>/dev/null || true
rm -f /home/ga/Downloads/*.xls 2>/dev/null || true

# 3. Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads

# 4. setup Firefox profile (standard clean profile)
# Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to a blank page or the starting point?
# Task description implies starting from blank or search, but opening blank is safer.
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox_launch.log 2>&1 &"

# 5. Wait for Firefox window
echo "Waiting for Firefox..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="