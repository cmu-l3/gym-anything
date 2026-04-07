#!/bin/bash
# Export script for LOC Catalog Research task
set -e

TASK_NAME="loc_catalog_research"
OUTPUT_FILE="/home/ga/Desktop/shelf_list.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
RESULT_JSON="/tmp/task_result.json"

echo "=== Exporting ${TASK_NAME} Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python script to gather verification data
python3 << 'PYEOF'
import json
import os
import sqlite3
import shutil
import tempfile
import time

result = {
    "output_file_exists": False,
    "output_file_content": "",
    "output_created_during_task": False,
    "history_visits_new": 0,
    "task_start_time": 0
}

# Load task start time
try:
    with open("/tmp/task_start_ts_loc_catalog_research.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    result["task_start_time"] = int(time.time()) - 600  # Fallback

# Check output file
output_path = "/home/ga/Desktop/shelf_list.txt"
if os.path.exists(output_path):
    result["output_file_exists"] = True
    
    # Check timestamp
    mtime = os.path.getmtime(output_path)
    if mtime > result["task_start_time"]:
        result["output_created_during_task"] = True
        
    # Read content
    try:
        with open(output_path, "r") as f:
            result["output_file_content"] = f.read()
    except Exception as e:
        result["output_file_content"] = f"Error reading file: {e}"

# Check History for LOC visits
history_path = "/home/ga/.config/microsoft-edge/Default/History"
baseline_path = "/tmp/task_baseline_history.json"
initial_visits = 0

if os.path.exists(baseline_path):
    try:
        with open(baseline_path, "r") as f:
            initial_visits = json.load(f).get("loc_visits", 0)
    except:
        pass

current_visits = 0
if os.path.exists(history_path):
    tmp_db = tempfile.mktemp(suffix=".sqlite")
    try:
        shutil.copy2(history_path, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%catalog.loc.gov%'")
        current_visits = cursor.fetchone()[0] or 0
        conn.close()
    except:
        pass
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)

result["history_visits_new"] = max(0, current_visits - initial_visits)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

echo "Result exported to ${RESULT_JSON}"