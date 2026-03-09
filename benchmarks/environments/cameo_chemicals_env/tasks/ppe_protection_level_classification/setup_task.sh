#!/bin/bash
set -e
echo "=== Setting up PPE Protection Level Classification task ==="

# Source shared utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/protective_clothing_report.txt

# Record initial file state
if [ -f "/home/ga/Documents/protective_clothing_report.txt" ]; then
    echo "exists" > /tmp/initial_file_state.txt
else
    echo "missing" > /tmp/initial_file_state.txt
fi

# Kill any existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox to CAMEO Chemicals..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process to start
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for Firefox window to appear
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Let page load
sleep 5

# Maximize and focus Firefox
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Firefox window maximized: $WINDOW_ID"
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== PPE Protection Level Classification task setup complete ==="