#!/bin/bash
# Export script for Travel Route Itinerary Research task

echo "=== Exporting Travel Route Itinerary Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python for robust data extraction
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import tempfile
import time

# Load task start time
try:
    task_start = int(open("/tmp/task_start_ts_travel_route_itinerary.txt").read().strip())
except:
    task_start = 0

# 1. Analyze Itinerary File
itinerary_path = "/home/ga/Desktop/pacific_coast_itinerary.txt"
file_exists = os.path.exists(itinerary_path)
file_stats = {"size": 0, "mtime": 0}
file_created_during_task = False

if file_exists:
    stats = os.stat(itinerary_path)
    file_stats["size"] = stats.st_size
    file_stats["mtime"] = int(stats.st_mtime)
    file_created_during_task = file_stats["mtime"] > task_start

# 2. Extract Browser History
history_path = "/home/ga/.config/microsoft-edge/Default/History"
visited_urls = []

if os.path.exists(history_path):
    # Copy to temp to avoid locks
    tmp_db = tempfile.mktemp(suffix=".sqlite3")
    try:
        shutil.copy2(history_path, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        # Get URLs visited after task start (converting chrome time to unix)
        # Chrome epoch is 1601-01-01. Difference to 1970-01-01 is 11644473600 seconds.
        # Timestamp is microseconds.
        # task_start (unix sec) -> chrome microsec: (task_start + 11644473600) * 1000000
        
        # Simpler: just get all URLs since we cleared history in setup
        cursor.execute("SELECT url, title, visit_count FROM urls")
        rows = cursor.fetchall()
        for r in rows:
            visited_urls.append({"url": r[0], "title": r[1], "count": r[2]})
        
        conn.close()
    except Exception as e:
        print(f"Error reading history: {e}")
    finally:
        if os.path.exists(tmp_db):
            os.unlink(tmp_db)

# 3. Construct Result JSON
result = {
    "task_start": task_start,
    "itinerary": {
        "exists": file_exists,
        "path": itinerary_path,
        "stats": file_stats,
        "created_during_task": file_created_during_task
    },
    "history": visited_urls,
    "timestamp": int(time.time())
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported result. File exists: {file_exists}, History items: {len(visited_urls)}")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="