#!/bin/bash
# setup_task.sh - Pre-task hook for flash_point_hot_work_assessment
set -e

echo "=== Setting up flash_point_hot_work_assessment task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean previous artifacts
OUTPUT_FILE="/home/ga/Documents/hot_work_flash_point_assessment.txt"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 3. Launch Firefox to CAMEO Chemicals
# Kill existing instances first to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox..."
TARGET_URL="https://cameochemicals.noaa.gov/"
su - ga -c "DISPLAY=:1 firefox -P default --no-remote '$TARGET_URL' > /tmp/firefox.log 2>&1 &"

# 4. Wait for Firefox to be ready
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Allow page load
sleep 5

# 5. Maximize and Focus
# Find window ID
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
else
    echo "WARNING: Could not find Firefox window to maximize."
fi

# 6. Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="