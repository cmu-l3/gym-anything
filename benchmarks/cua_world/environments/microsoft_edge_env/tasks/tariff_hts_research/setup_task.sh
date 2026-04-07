#!/bin/bash
# Setup for Tariff HTS Research task
set -e

TASK_NAME="tariff_hts_research"
REPORT_FILE="/home/ga/Desktop/tariff_classification.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
DOWNLOADS_DIR="/home/ga/Downloads"

echo "=== Setting up ${TASK_NAME} ==="

# 1. Kill any running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Clean up previous artifacts
echo "Cleaning up previous artifacts..."
rm -f "${REPORT_FILE}"
# We generally preserve Downloads to emulate a real user, but for this task 
# we want to verify a NEW download, so we'll record the state later.
mkdir -p "${DOWNLOADS_DIR}"
chown ga:ga "${DOWNLOADS_DIR}"

# 3. Record task start timestamp (Anti-gaming)
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 4. Record baseline browser history counts
# This allows us to detect NEW visits even if history wasn't cleared
echo "Recording baseline history..."
python3 << 'PYEOF'
import sqlite3, shutil, json, os, sys

history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/history_baseline.sqlite"
baseline_path = "/tmp/history_baseline_counts.json"

baseline = {"usitc_count": 0, "cbp_count": 0}

if os.path.exists(history_src):
    try:
        # Copy to avoid locking issues
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()
        
        # Count visits to key domains
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%usitc.gov%'")
        baseline["usitc_count"] = cur.fetchone()[0] or 0
        
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%cbp.gov%'")
        baseline["cbp_count"] = cur.fetchone()[0] or 0
        
        conn.close()
        os.remove(history_tmp)
    except Exception as e:
        print(f"Warning: could not read history: {e}", file=sys.stderr)

with open(baseline_path, "w") as f:
    json.dump(baseline, f)
PYEOF

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
# Launching with specific flags to ensure clean automation environment
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

# Ensure window is maximized
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="