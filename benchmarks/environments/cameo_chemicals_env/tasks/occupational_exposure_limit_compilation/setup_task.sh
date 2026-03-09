#!/bin/bash
# setup_task.sh - Setup for Occupational Exposure Limit Compilation
set -e

echo "=== Setting up Occupational Exposure Limit Compilation Task ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback if utils not found (for testing isolation)
    function kill_firefox() { pkill -u ga -f firefox 2>/dev/null || true; }
    function maximize_firefox() { 
        WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
        [ -n "$WID" ] && DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null
    }
    function take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Record task start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean environment
echo "Cleaning up previous run artifacts..."
rm -f /home/ga/Documents/exposure_limits_report.txt 2>/dev/null || true
# Create parent directory just in case
sudo -u ga mkdir -p /home/ga/Documents

# 3. Prepare Browser
echo "Preparing Firefox..."
kill_firefox ga

# Launch Firefox to CAMEO Chemicals
# We use nohup/backgrounding to ensure it stays running
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process
echo "Waiting for Firefox process..."
for i in {1..45}; do
    if pgrep -u ga -f firefox > /dev/null; then
        break
    fi
    sleep 1
done

# Wait for Window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Allow page load
sleep 5

# Maximize and Focus
maximize_firefox
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 4. Initial Evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="