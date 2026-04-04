#!/bin/bash
# setup_task.sh - Pre-task hook for nfpa_rating_compilation

echo "=== Setting up NFPA Rating Compilation Task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# 1. Clean up previous artifacts
REPORT_FILE="/home/ga/Desktop/nfpa_report.txt"
if [ -f "$REPORT_FILE" ]; then
    echo "Removing existing report file..."
    rm -f "$REPORT_FILE"
fi

# 2. Ensure Desktop directory exists
sudo -u ga mkdir -p /home/ga/Desktop

# 3. Launch Firefox to CAMEO Chemicals homepage
# Using a fresh instance to ensure clean state
echo "Killing existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox..."
# Launch directly to homepage
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# 4. Wait for Firefox to appear
TIMEOUT=45
ELAPSED=0
echo "Waiting for Firefox window..."
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window found after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# 5. Maximize the window
sleep 3
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 6. Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="