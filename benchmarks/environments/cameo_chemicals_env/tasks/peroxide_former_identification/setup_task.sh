#!/bin/bash
set -e
echo "=== Setting up Peroxide Former Identification Task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous run artifacts
OUTPUT_FILE="/home/ga/Desktop/peroxide_audit_report.txt"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing report file..."
    rm -f "$OUTPUT_FILE"
fi

# Ensure Desktop exists
sudo -u ga mkdir -p /home/ga/Desktop

# Kill any existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox to appear
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Sleep to allow page load
sleep 5

# Maximize the window (important for VLM visibility)
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="