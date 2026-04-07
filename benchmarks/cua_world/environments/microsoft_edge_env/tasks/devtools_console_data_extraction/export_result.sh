#!/bin/bash
# Export script for DevTools Console Data Extraction task

echo "=== Exporting DevTools Console Data Extraction Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Python script to gather all evidence into a JSON
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import tempfile
import time

# 1. Get Task Start Time
task_start = 0
try:
    with open("/tmp/task_start_ts_devtools_console_data_extraction.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    pass

# 2. Check CSV File
csv_path = "/home/ga/Desktop/country_populations.csv"
csv_info = {
    "exists": False,
    "size": 0,
    "mtime": 0,
    "created_during_task": False
}

if os.path.exists(csv_path):
    stat = os.stat(csv_path)
    csv_info["exists"] = True
    csv_info["size"] = stat.st_size
    csv_info["mtime"] = int(stat.st_mtime)
    csv_info["created_during_task"] = csv_info["mtime"] > task_start

# 3. Check Log File
log_path = "/home/ga/Desktop/extraction_log.txt"
log_info = {
    "exists": False,
    "created_during_task": False
}
if os.path.exists(log_path):
    stat = os.stat(log_path)
    log_info["exists"] = True
    log_info["created_during_task"] = int(stat.st_mtime) > task_start

# 4. Check Browser History for Wikipedia visit
# Query Edge history (copy first to avoid lock)
history_path = "/home/ga/.config/microsoft-edge/Default/History"
wikipedia_visited = False

if os.path.exists(history_path):
    tmp_hist = tempfile.mktemp(suffix=".sqlite3")
    try:
        shutil.copy2(history_path, tmp_hist)
        conn = sqlite3.connect(tmp_hist)
        cursor = conn.cursor()
        # Look for the specific population page or at least wikipedia
        cursor.execute("SELECT count(*) FROM urls WHERE url LIKE '%wikipedia.org%population%'")
        count = cursor.fetchone()[0]
        if count > 0:
            wikipedia_visited = True
        conn.close()
    except Exception as e:
        print(f"History check failed: {e}")
    finally:
        if os.path.exists(tmp_hist):
            os.unlink(tmp_hist)

# 5. Compile Result
result = {
    "task_start": task_start,
    "csv_file": csv_info,
    "log_file": log_info,
    "wikipedia_visited": wikipedia_visited,
    "timestamp": int(time.time())
}

# Write to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="