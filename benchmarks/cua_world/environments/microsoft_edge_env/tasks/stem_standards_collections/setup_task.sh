#!/bin/bash
# Setup for STEM Standards Research task
# Kills Edge, clears history/collections for clean state, launches Edge.

set -e

TASK_NAME="stem_standards_collections"
OUTPUT_FILE="/home/ga/Desktop/stem_standards_reference.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
EDGE_CONFIG_DIR="/home/ga/.config/microsoft-edge/Default"

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

# ── STEP 2: Clean up artifacts ───────────────────────────────────────────────
echo "[2/5] Cleaning up previous artifacts..."
rm -f "${OUTPUT_FILE}"

# Reset Collections (delete the database directory so it starts fresh)
# Edge uses a LevelDB database for Collections usually located in "Collections" folder
if [ -d "${EDGE_CONFIG_DIR}/Collections" ]; then
    echo "Resetting Collections database..."
    rm -rf "${EDGE_CONFIG_DIR}/Collections"
fi

# Clear History to ensure clean verification
if [ -f "${EDGE_CONFIG_DIR}/History" ]; then
    echo "Clearing Browser History..."
    rm -f "${EDGE_CONFIG_DIR}/History"
    rm -f "${EDGE_CONFIG_DIR}/History-journal"
fi

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/5] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Launch Edge ──────────────────────────────────────────────────────
echo "[4/5] Launching Microsoft Edge..."
# Launch with standard flags for automation stability
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
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

# Maximize explicitly to be safe
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# ── STEP 5: Initial Screenshot ──────────────────────────────────────────────
echo "[5/5] Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete for ${TASK_NAME} ==="