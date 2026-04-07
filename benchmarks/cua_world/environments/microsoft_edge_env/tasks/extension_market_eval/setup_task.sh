#!/bin/bash
# Setup for Extension Market Eval task
set -e

TASK_NAME="extension_market_eval"
OUTPUT_FILE="/home/ga/Desktop/extension_comparison.csv"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"

echo "=== Setting up ${TASK_NAME} ==="

# 1. Kill any running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Remove any existing output files
echo "Cleaning up previous results..."
rm -f "${OUTPUT_FILE}"

# 3. Record task start timestamp for anti-gaming verification
echo "Recording start timestamp..."
date +%s > "${START_TS_FILE}"

# 4. Clear Edge history to ensure we track *new* visits
# (Optional but helpful for strict verification of 'research' activity)
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
if [ -f "$HISTORY_DB" ]; then
    rm "$HISTORY_DB" 2>/dev/null || true
fi

# 5. Launch Edge
echo "Launching Microsoft Edge..."
# Launch with specific flags to ensure clean environment but allow normal web usage
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

# Ensure window is maximized
sleep 2
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="