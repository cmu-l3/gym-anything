#!/bin/bash
# Export script for client_storage_privacy_audit task

echo "=== Exporting Client Storage Privacy Audit Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Kill Edge to ensure DB flush (optional but safe)
pkill -u ga -f microsoft-edge 2>/dev/null || true
sleep 2

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
    with open("/tmp/task_start_ts_client_storage_privacy_audit.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = int(time.time()) - 600  # Fallback

# 2. Analyze Report File
report_path = "/home/ga/Desktop/storage_audit_report.txt"
report_info = {
    "exists": False,
    "size_bytes": 0,
    "modified_after_start": False
}

if os.path.exists(report_path):
    stat = os.stat(report_path)
    report_info["exists"] = True
    report_info["size_bytes"] = stat.st_size
    report_info["modified_after_start"] = stat.st_mtime > task_start

# 3. Analyze Browser History
# Since we deleted History at setup, any entries here are new.
history_path = "/home/ga/.config/microsoft-edge/Default/History"
history_data = {
    "wikipedia": False,
    "github": False,
    "reddit": False,
    "total_visits": 0
}

if os.path.exists(history_path):
    tmp_db = tempfile.mktemp(suffix=".sqlite3")
    try:
        shutil.copy2(history_path, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        
        # Check visits
        # We use strict domain matching to avoid false positives from search engine results
        domains = {
            "wikipedia": "%wikipedia.org%",
            "github": "%github.com%",
            "reddit": "%reddit.com%"
        }
        
        for key, pattern in domains.items():
            cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE ?", (pattern,))
            count = cursor.fetchone()[0]
            if count > 0:
                history_data[key] = True
        
        cursor.execute("SELECT COUNT(*) FROM urls")
        history_data["total_visits"] = cursor.fetchone()[0]
        
        conn.close()
    except Exception as e:
        print(f"Error reading history: {e}")
    finally:
        if os.path.exists(tmp_db):
            os.unlink(tmp_db)

# 4. Compile Result
result = {
    "task_start": task_start,
    "report": report_info,
    "history": history_data,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Result summary:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="