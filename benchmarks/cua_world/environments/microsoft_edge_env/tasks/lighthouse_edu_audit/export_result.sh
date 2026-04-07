#!/bin/bash
# Export script for Lighthouse Accessibility Audit task
# Captures report content, history visits, and final state.

echo "=== Exporting Lighthouse Audit Result ==="

TASK_NAME="lighthouse_edu_audit"
REPORT_PATH="/home/ga/Desktop/lighthouse_audit_report.txt"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python to analyze state and produce JSON
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import tempfile
import time

# 1. Get Task Start Time
try:
    with open(f"/tmp/task_start_ts_lighthouse_edu_audit.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 2. Analyze Report File
report_info = {
    "exists": False,
    "size": 0,
    "mtime": 0,
    "modified_after_start": False,
    "content_preview": ""
}

report_path = "/home/ga/Desktop/lighthouse_audit_report.txt"
if os.path.exists(report_path):
    stat = os.stat(report_path)
    report_info["exists"] = True
    report_info["size"] = stat.st_size
    report_info["mtime"] = int(stat.st_mtime)
    report_info["modified_after_start"] = stat.st_mtime > task_start
    
    # Read content safely
    try:
        with open(report_path, "r", errors="ignore") as f:
            report_info["content_preview"] = f.read()
    except Exception as e:
        report_info["read_error"] = str(e)

# 3. Analyze Browser History for Site Visits
# Chrome/Edge History timestamps are microseconds since Jan 1, 1601
# Unix epoch (Jan 1 1970) is 11644473600 seconds after Windows epoch.
# Current Unix time * 1,000,000 + 11644473600000000 = Windows timestamp
def unix_to_webkit(unix_ts):
    return (unix_ts * 1000000) + 11644473600000000

history_check = {
    "khan_visited": False,
    "coursera_visited": False,
    "mit_visited": False
}

history_db = "/home/ga/.config/microsoft-edge/Default/History"
if os.path.exists(history_db):
    # Copy DB to avoid locks
    tmp_db = tempfile.mktemp(suffix=".sqlite")
    try:
        shutil.copy2(history_db, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        
        # Query for visits after task start
        start_webkit = unix_to_webkit(task_start)
        
        domains = {
            "khan_visited": "%khanacademy.org%",
            "coursera_visited": "%coursera.org%",
            "mit_visited": "%ocw.mit.edu%"
        }
        
        for key, pattern in domains.items():
            query = "SELECT count(*) FROM urls WHERE url LIKE ? AND last_visit_time > ?"
            cursor.execute(query, (pattern, start_webkit))
            count = cursor.fetchone()[0]
            if count > 0:
                history_check[key] = True
                
        conn.close()
    except Exception as e:
        history_check["error"] = str(e)
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)

# 4. Compile Result
result = {
    "task_start": task_start,
    "timestamp": time.time(),
    "report": report_info,
    "history": history_check
}

with open("/tmp/lighthouse_edu_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "Result JSON generated at /tmp/${TASK_NAME}_result.json"