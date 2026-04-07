#!/bin/bash
# Export script for iFixit Repair Checklist Creation task

echo "=== Exporting Results ==="

TASK_NAME="ifixit_repair_checklist_creation"
OUTPUT_FILE="/home/ga/Desktop/iphone13_battery_checklist.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_final.png 2>/dev/null || true

# 2. Python script to analyze results
python3 << 'PYEOF'
import json
import os
import sqlite3
import shutil
import time

output_path = "/home/ga/Desktop/iphone13_battery_checklist.txt"
start_ts_path = "/tmp/task_start_ts_ifixit_repair_checklist_creation.txt"
history_db = "/home/ga/.config/microsoft-edge/Default/History"

# Get task start time
try:
    with open(start_ts_path, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Check output file
file_exists = False
file_content = ""
file_modified_time = 0
created_during_task = False

if os.path.exists(output_path):
    file_exists = True
    file_modified_time = int(os.path.getmtime(output_path))
    created_during_task = file_modified_time > task_start
    try:
        with open(output_path, 'r', encoding='utf-8', errors='ignore') as f:
            file_content = f.read()
    except Exception as e:
        file_content = f"Error reading file: {str(e)}"

# Check Browser History
visited_ifixit = False
visited_target_guide = False
history_urls = []

if os.path.exists(history_db):
    try:
        # Copy DB to temp file to avoid locks
        tmp_db = "/tmp/history_check.sqlite"
        shutil.copy2(history_db, tmp_db)
        
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        cursor.execute("SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 20")
        rows = cursor.fetchall()
        
        for url, title in rows:
            history_urls.append(url)
            if "ifixit.com" in url:
                visited_ifixit = True
            # Specific check for iPhone 13 Battery guide
            # URL usually looks like: https://www.ifixit.com/Guide/iPhone+13+Battery+Replacement/145896
            if "ifixit.com/Guide/iPhone+13+Battery+Replacement" in url or \
               ("ifixit.com" in url and "iPhone 13" in title and "Battery" in title):
                visited_target_guide = True
                
        conn.close()
        os.remove(tmp_db)
    except Exception as e:
        print(f"History check error: {e}")

# Compile result
result = {
    "file_exists": file_exists,
    "created_during_task": created_during_task,
    "file_content": file_content,
    "visited_ifixit": visited_ifixit,
    "visited_target_guide": visited_target_guide,
    "history_sample": history_urls,
    "timestamp": time.time()
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="