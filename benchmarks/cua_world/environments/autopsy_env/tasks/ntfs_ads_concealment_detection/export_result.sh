#!/bin/bash
echo "=== Exporting results for NTFS ADS Concealment Detection task ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to ensure SQLite databases are flushed and locks are released
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json
import os
import glob
import sqlite3

result = {
    "task": "ntfs_ads_concealment_detection",
    "case_db_found": False,
    "tsk_cli_used": False,
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# 1. Get task start time
try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. Check for Autopsy DB initialization
db_paths = glob.glob("/home/ga/Cases/ADS_Investigation_2024*/autopsy.db")
if db_paths:
    result["case_db_found"] = True

# 3. Check for Sleuth Kit CLI usage in bash history
try:
    with open("/home/ga/.bash_history", "r", errors="ignore") as f:
        history = f.read()
        if "fls " in history or "icat " in history or "mmls " in history:
            result["tsk_cli_used"] = True
except Exception:
    pass

# 4. Extract CSV report
csv_path = "/home/ga/Reports/ads_findings.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    try:
        with open(csv_path, "r", encoding="utf-8", errors="replace") as f:
            result["csv_content"] = f.read(10240) # Read up to 10KB
    except Exception as e:
        result["error"] += f" Failed to read CSV: {e}"

# 5. Extract Summary report
summary_path = "/home/ga/Reports/ads_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    try:
        with open(summary_path, "r", encoding="utf-8", errors="replace") as f:
            result["summary_content"] = f.read(2048)
    except Exception as e:
        result["error"] += f" Failed to read Summary: {e}"

# Safely write the JSON result
with open("/tmp/ads_task_result_temp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move temp file to final destination safely
mv /tmp/ads_task_result_temp.json /tmp/ads_task_result.json
chmod 666 /tmp/ads_task_result.json

echo "Result JSON written to /tmp/ads_task_result.json"
cat /tmp/ads_task_result.json
echo "=== Export complete ==="