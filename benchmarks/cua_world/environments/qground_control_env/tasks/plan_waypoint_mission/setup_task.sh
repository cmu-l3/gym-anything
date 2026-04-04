#!/bin/bash
echo "=== Setting up plan_waypoint_mission task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 2. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 3. Prepare real mission data for reference
echo "--- Preparing mission data ---"
mkdir -p /home/ga/Documents/QGC
if [ -f /workspace/data/sample_mission.plan ]; then
    cp /workspace/data/sample_mission.plan /home/ga/Documents/QGC/sample_mission.plan
    chown ga:ga /home/ga/Documents/QGC/sample_mission.plan
    echo "Sample mission copied to /home/ga/Documents/QGC/"
else
    echo "WARNING: sample_mission.plan not found in /workspace/data/"
fi

# 4. Focus and maximize QGC
echo "--- Focusing QGC window ---"
sleep 2
maximize_qgc
sleep 1

# 5. Dismiss any lingering dialogs
dismiss_dialogs

# 6. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png

echo "=== plan_waypoint_mission task setup complete ==="
