#!/bin/bash
# Setup for iFixit Repair Checklist Creation task

set -e

TASK_NAME="ifixit_repair_checklist_creation"
OUTPUT_FILE="/home/ga/Desktop/iphone13_battery_checklist.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any running Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Remove any existing output file
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing output file..."
    rm -f "$OUTPUT_FILE"
fi

# 3. Record task start timestamp (Anti-gaming)
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 4. Clear browser history for clean verification
# (Optional but helps verify specific task actions)
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
if [ -f "$HISTORY_DB" ]; then
    echo "Clearing history..."
    rm -f "$HISTORY_DB" "$HISTORY_DB-journal"
fi

# 5. Launch Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    > /tmp/edge.log 2>&1 &"

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
DISPLAY=:1 scrot /tmp/${TASK_NAME}_initial.png 2>/dev/null || true

echo "=== Setup complete ==="