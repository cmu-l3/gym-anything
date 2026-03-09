#!/bin/bash
echo "=== Setting up CERCLA RQ Assessment Task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/cercla_spill_report.txt
sudo -u ga mkdir -p /home/ga/Documents

# 2. Ensure clean browser state
echo "Cleaning up browser state..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# 4. Wait for window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# 5. Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 6. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="