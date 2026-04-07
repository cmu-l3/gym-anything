#!/bin/bash
# Setup for Library of Congress Catalog Research task
set -e

TASK_NAME="loc_catalog_research"
OUTPUT_FILE="/home/ga/Desktop/shelf_list.txt"
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
if [ -f "${OUTPUT_FILE}" ]; then
    echo "Removing existing output file..."
    rm -f "${OUTPUT_FILE}"
fi

# 3. Record task start timestamp (Anti-gaming)
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 4. Record baseline history for catalog.loc.gov
echo "Recording baseline history..."
python3 << 'PYEOF'
import sqlite3, shutil, json, os

history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/history_baseline.sqlite"
baseline_path = "/tmp/task_baseline_history.json"

baseline = {"loc_visits": 0}

if os.path.exists(history_src):
    try:
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()
        # Count visits to Library of Congress catalog
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%catalog.loc.gov%'")
        baseline["loc_visits"] = cur.fetchone()[0] or 0
        conn.close()
        os.remove(history_tmp)
    except Exception as e:
        print(f"Warning: could not read history: {e}")

with open(baseline_path, "w") as f:
    json.dump(baseline, f)
PYEOF

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge window
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
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete for ${TASK_NAME} ==="