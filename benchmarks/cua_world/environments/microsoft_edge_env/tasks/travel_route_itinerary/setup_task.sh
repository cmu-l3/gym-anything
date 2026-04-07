#!/bin/bash
# Setup for Travel Route Itinerary Research task
# Ensures clean browser state and records start timestamp

set -e

TASK_NAME="travel_route_itinerary"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
ITINERARY_FILE="/home/ga/Desktop/pacific_coast_itinerary.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill any running Edge instances ──────────────────────────────────
echo "[1/4] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Clear previous artifacts ─────────────────────────────────────────
echo "[2/4] Removing stale files..."
rm -f "${ITINERARY_FILE}"
# Clean history to ensure verification only counts current session
rm -f "/home/ga/.config/microsoft-edge/Default/History" 2>/dev/null || true
rm -f "/home/ga/.config/microsoft-edge/Default/History-journal" 2>/dev/null || true

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/4] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Launch Edge and take start screenshot ────────────────────────────
echo "[4/4] Launching Microsoft Edge..."
# Launch to a blank tab or a neutral search page
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank \
    > /tmp/edge.log 2>&1 &"

# Wait for Edge window to appear
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="