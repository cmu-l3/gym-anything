#!/bin/bash
# setup_task.sh - Pre-task hook for brand_visual_audit
# Prepares environment: kills Edge, removes old reports, records start time

set -e

echo "=== Setting up Brand Visual Audit task ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any existing Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Remove any existing report file
REPORT_PATH="/home/ga/Desktop/brand_audit.txt"
if [ -f "$REPORT_PATH" ]; then
    echo "Removing existing report file..."
    rm -f "$REPORT_PATH"
fi

# 3. Record task start time (Unix timestamp)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
# Launch with specific flags to ensure clean automation profile
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --disable-extensions \
    --disable-component-update \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# 5. Wait for Edge window
echo "Waiting for Edge window..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# 6. Maximize window
sleep 2
echo "Maximizing Edge window..."
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="