#!/bin/bash
# Setup for DevTools Console Data Extraction task
# Kills Edge, cleans Desktop, records start time, and launches Edge.

set -e

TASK_NAME="devtools_console_data_extraction"
CSV_FILE="/home/ga/Desktop/country_populations.csv"
LOG_FILE="/home/ga/Desktop/extraction_log.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill any running Edge instances ──────────────────────────────────
echo "[1/5] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Clean up previous run artifacts ──────────────────────────────────
echo "[2/5] Cleaning Desktop..."
rm -f "${CSV_FILE}"
rm -f "${LOG_FILE}"

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/5] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Ensure Desktop exists ────────────────────────────────────────────
sudo -u ga mkdir -p /home/ga/Desktop

# ── STEP 5: Launch Edge on a blank page ──────────────────────────────────────
echo "[5/5] Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

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

# Maximize window
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="