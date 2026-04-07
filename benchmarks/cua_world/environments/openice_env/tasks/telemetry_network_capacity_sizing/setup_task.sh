#!/bin/bash
echo "=== Setting up telemetry_network_capacity_sizing task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure OpenICE is running
ensure_openice_running

# 3. Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# 4. Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Ensure clean state: Remove any existing report file
rm -f /home/ga/Desktop/capacity_plan.txt 2>/dev/null || true

# 6. Record initial window count (to detect if agent creates device)
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# 7. Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="