#!/bin/bash
echo "=== Setting up change_flight_parameter task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 2. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 3. Focus and maximize QGC
echo "--- Focusing QGC window ---"
sleep 2
maximize_qgc
sleep 1

# 4. Dismiss any lingering dialogs
dismiss_dialogs

# 5. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png

echo "=== change_flight_parameter task setup complete ==="
