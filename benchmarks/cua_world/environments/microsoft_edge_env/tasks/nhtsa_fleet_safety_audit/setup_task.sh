#!/bin/bash
# Setup for NHTSA Fleet Safety Audit
# Cleans environment, ensures Edge is ready, and timestamps start.

set -e

TASK_NAME="nhtsa_fleet_safety_audit"
REPORT_FILE="/home/ga/Desktop/fleet_safety_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
DOWNLOADS_DIR="/home/ga/Downloads"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill existing Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 1
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# 2. Clean up previous artifacts
echo "Cleaning up artifacts..."
rm -f "${REPORT_FILE}"
# Clean downloads but keep the directory
rm -rf "${DOWNLOADS_DIR}"/*

# 3. Record start timestamp for anti-gaming
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 4. Record baseline history count (to verify new visits)
python3 << 'PYEOF'
import sqlite3, shutil, os

history_path = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/nhtsa_history_baseline.txt"
count = 0

if os.path.exists(history_path):
    try:
        # Copy to temp to avoid locks
        shutil.copy2(history_path, "/tmp/history_temp.db")
        conn = sqlite3.connect("/tmp/history_temp.db")
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%nhtsa.gov%'")
        count = cursor.fetchone()[0]
        conn.close()
        os.remove("/tmp/history_temp.db")
    except Exception as e:
        print(f"Error reading history: {e}")

with open(baseline_file, "w") as f:
    f.write(str(count))
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

# Wait for Edge to appear
TIMEOUT=30
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="