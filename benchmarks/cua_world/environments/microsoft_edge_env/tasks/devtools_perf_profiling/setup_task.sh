#!/bin/bash
# Setup for DevTools Performance Profiling task

set -e

TASK_NAME="devtools_perf_profiling"
REPORT_FILE="/home/ga/Desktop/performance_profile_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Remove any existing report file
if [ -f "${REPORT_FILE}" ]; then
    echo "Removing existing report file..."
    rm -f "${REPORT_FILE}"
fi

# 3. Record task start timestamp (for anti-gaming)
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 4. Record baseline history state
# We check history counts for target domains to ensure they are visited *during* the task
python3 << 'PYEOF'
import sqlite3, shutil, json, os

history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/history_baseline.json"
domains = ["cnn.com", "wikipedia.org", "github.com"]
counts = {}

if os.path.exists(history_db):
    try:
        # Copy to temp to avoid locks
        temp_db = "/tmp/history_snap_setup.sqlite"
        shutil.copy2(history_db, temp_db)
        
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        for domain in domains:
            query = f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%'"
            cursor.execute(query)
            counts[domain] = cursor.fetchone()[0]
            
        conn.close()
        os.remove(temp_db)
    except Exception as e:
        print(f"Error reading history: {e}")

with open(baseline_file, 'w') as f:
    json.dump(counts, f)
print(f"Baseline history counts saved to {baseline_file}")
PYEOF

# 5. Launch Edge on a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank \
    > /tmp/edge.log 2>&1 &"

# Wait for Edge window
TIMEOUT=30
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window appeared."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="