#!/bin/bash
# Setup for CSS Live Prototyping task

set -e

echo "=== Setting up css_live_prototyping task ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any running Edge instances
echo "Killing existing Edge processes..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 2. Clean up previous artifacts
echo "Cleaning up artifacts..."
rm -f /home/ga/Desktop/mockup.png
rm -f /home/ga/Desktop/new_styles.css
rm -f /tmp/task_result.json

# 3. Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Record initial history state (to detect new visits later)
# We'll rely on timestamps in the verification, but knowing the DB state helps
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
if [ -f "$HISTORY_DB" ]; then
    cp "$HISTORY_DB" /tmp/history_initial.db
else
    echo "No existing history DB found."
fi

# 5. Launch Microsoft Edge (blank state)
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --start-maximized \
    --password-store=basic \
    about:blank > /dev/null 2>&1 &"

# Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Focus Edge
DISPLAY=:1 wmctrl -a "Microsoft Edge" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="