#!/bin/bash
# Setup for LOC Historical Poster Archival task

set -e
echo "=== Setting up loc_historical_poster_archival task ==="

# Source utilities
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Clean up previous artifacts
TARGET_DIR="/home/ga/Pictures/WPA_Travel"
echo "Cleaning up $TARGET_DIR..."
rm -rf "$TARGET_DIR"

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Kill existing Edge instances
echo "Killing Edge instances..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 1

# 4. Record baseline history (to verify they actually visit LOC)
echo "Recording history baseline..."
python3 << 'PYEOF'
import sqlite3, shutil, os
history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/history_baseline_count.txt"
count = 0
if os.path.exists(history_db):
    try:
        # Copy to temp to avoid locks
        shutil.copy2(history_db, "/tmp/history_temp.db")
        conn = sqlite3.connect("/tmp/history_temp.db")
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%loc.gov%'")
        count = cursor.fetchone()[0]
        conn.close()
        os.remove("/tmp/history_temp.db")
    except Exception as e:
        print(f"Error reading history: {e}")

with open(baseline_file, "w") as f:
    f.write(str(count))
PYEOF

# 5. Launch Edge to a neutral page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge --no-first-run --no-default-browser-check --start-maximized 'about:blank' > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for Edge..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window found."
        break
    fi
    sleep 1
done

# Maximize explicitly to be safe
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="