#!/bin/bash
# Setup for Responsive Design Audit task

set -e

echo "=== Setting up Responsive Design Audit Task ==="

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

# 2. Clean up previous run artifacts
OUTPUT_DIR="/home/ga/Desktop/responsive_audit"
if [ -d "$OUTPUT_DIR" ]; then
    echo "Removing existing output directory..."
    rm -rf "$OUTPUT_DIR"
fi

# 3. Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# 4. Record initial browser history state (to detect new visits)
# We'll use a simple count of visits to the target domains
python3 << 'PYEOF'
import sqlite3, shutil, json, os

history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/history_baseline.json"
domains = ["usa.gov", "weather.gov", "nasa.gov"]
counts = {}

if os.path.exists(history_db):
    try:
        # Copy to tmp to avoid locking
        shutil.copy2(history_db, "/tmp/history_copy.sqlite")
        conn = sqlite3.connect("/tmp/history_copy.sqlite")
        cursor = conn.cursor()
        for domain in domains:
            try:
                cursor.execute(f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%'")
                counts[domain] = cursor.fetchone()[0]
            except:
                counts[domain] = 0
        conn.close()
        os.remove("/tmp/history_copy.sqlite")
    except Exception as e:
        print(f"Error reading history: {e}")

with open(baseline_file, 'w') as f:
    json.dump(counts, f)
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
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="