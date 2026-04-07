#!/bin/bash
# setup_task.sh for offline_field_references
set -e

echo "=== Setting up Offline Field References Task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up Previous Run Artifacts
TARGET_DIR="/home/ga/Documents/offline_references"
if [ -d "$TARGET_DIR" ]; then
    echo "Removing existing target directory..."
    rm -rf "$TARGET_DIR"
fi

# 3. Kill Existing Edge Instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 4. Record Baseline History (to verify new visits)
# We use a python script to snapshot the current history counts for target domains
python3 << 'PYEOF'
import sqlite3
import shutil
import os
import json

history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/history_baseline.json"
domains = ["usda.gov", "epa.gov", "nass.usda.gov"]
counts = {d: 0 for d in domains}

if os.path.exists(history_db):
    try:
        # Copy to temp to avoid lock
        shutil.copy2(history_db, "/tmp/history_snapshot.db")
        conn = sqlite3.connect("/tmp/history_snapshot.db")
        cursor = conn.cursor()
        for domain in domains:
            query = f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%'"
            cursor.execute(query)
            counts[domain] = cursor.fetchone()[0]
        conn.close()
        os.remove("/tmp/history_snapshot.db")
    except Exception as e:
        print(f"Error reading history: {e}")

with open(baseline_file, 'w') as f:
    json.dump(counts, f)
print("History baseline recorded.")
PYEOF

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# 6. Wait for Edge Window and Maximize
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window found."
        break
    fi
    sleep 1
done
sleep 2

# Maximize
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="