#!/bin/bash
set -e
echo "=== Setting up Freezing/Solidification Risk Assessment Task ==="

# Source shared utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    echo "Warning: task_utils.sh not found, defining local fallbacks"
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# 2. Ensure clean state
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Documents/freezing_risk_report.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Kill any existing Firefox instances
echo "Killing existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 4. Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# 5. Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and focus the window
echo "Configuring window..."
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    echo "Window maximized: $WID"
else
    echo "WARNING: Could not find Firefox window ID to maximize."
fi

# 7. Take initial screenshot (Evidence of correct start state)
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="