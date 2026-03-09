#!/bin/bash
# setup_task.sh for incompatible_absorbent_screening
set -e

echo "=== Setting up Incompatible Absorbent Screening Task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Prepare Environment
# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any existing report file to ensure a fresh start
rm -f /home/ga/Documents/absorbent_safety_audit.txt 2>/dev/null || true

# 3. Setup Firefox
# Kill existing instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox_task.log 2>&1 &"

# 4. Wait for Application
# Wait for process
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for window
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Allow page to load
sleep 5

# 5. Configure Window (Maximize and Focus)
# Get Window ID
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 6. Capture Initial State Screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="