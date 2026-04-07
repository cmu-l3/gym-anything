#!/bin/bash
# Export script for DevTools Performance Profiling task

echo "=== Exporting DevTools Performance Profiling Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

REPORT_FILE="/home/ga/Desktop/performance_profile_report.txt"
START_TS_FILE="/tmp/task_start_ts_devtools_perf_profiling.txt"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to analyze results and generate JSON
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import time
import re

# 1. Get Task Start Time
start_time = 0
try:
    with open("/tmp/task_start_ts_devtools_perf_profiling.txt", "r") as f:
        start_time = int(f.read().strip())
except:
    start_time = time.time() - 600 # Fallback

# 2. Analyze Report File
report_info = {
    "exists": False,
    "modified_after_start": False,
    "size": 0,
    "content": "",
    "domains_mentioned": [],
    "performance_terms_count": 0,
    "has_timing_data": False
}

report_path = "/home/ga/Desktop/performance_profile_report.txt"
if os.path.exists(report_path):
    stat = os.stat(report_path)
    report_info["exists"] = True
    report_info["size"] = stat.st_size
    report_info["modified_after_start"] = stat.st_mtime > start_time
    
    try:
        with open(report_path, "r", errors="ignore") as f:
            content = f.read()
            report_info["content"] = content
            
            # Check content
            lower_content = content.lower()
            for domain in ["cnn", "wikipedia", "github"]:
                if domain in lower_content:
                    report_info["domains_mentioned"].append(domain)
            
            terms = ["scripting", "rendering", "painting", "loading", "idle"]
            found_terms = [t for t in terms if t in lower_content]
            report_info["performance_terms_count"] = len(found_terms)
            
            # Regex for timing (e.g., "123 ms", "1.2s", "400ms")
            timing_match = re.search(r'\d+(\.\d+)?\s*(ms|s)\b', lower_content)
            if timing_match:
                report_info["has_timing_data"] = True
    except Exception as e:
        print(f"Error reading report: {e}")

# 3. Analyze Browser History (New Visits)
history_info = {
    "cnn_visited": False,
    "wikipedia_visited": False,
    "github_visited": False
}

history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/history_baseline.json"
baseline_counts = {}

if os.path.exists(baseline_file):
    try:
        with open(baseline_file, "r") as f:
            baseline_counts = json.load(f)
    except:
        pass

if os.path.exists(history_db):
    try:
        temp_db = "/tmp/history_snap_export.sqlite"
        shutil.copy2(history_db, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        domains = ["cnn.com", "wikipedia.org", "github.com"]
        for domain in domains:
            query = f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%'"
            cursor.execute(query)
            current_count = cursor.fetchone()[0]
            initial_count = baseline_counts.get(domain, 0)
            
            key = domain.split('.')[0] + "_visited" # e.g., cnn_visited
            if current_count > initial_count:
                history_info[key] = True
            
            # Backup check: check if any visit has last_visit_time > start_time
            # Edge time is microseconds since 1601-01-01. 
            # Unix epoch (1970) is 11644473600 seconds after 1601.
            # Convert unix start_time to webkit time
            webkit_start = (start_time + 11644473600) * 1000000
            
            time_query = f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%' AND last_visit_time > {webkit_start}"
            cursor.execute(time_query)
            recent_visits = cursor.fetchone()[0]
            if recent_visits > 0:
                history_info[key] = True

        conn.close()
        os.remove(temp_db)
    except Exception as e:
        print(f"Error checking history: {e}")

# 4. Check App State
app_running = False
try:
    if os.system("pgrep -f 'microsoft-edge' > /dev/null") == 0:
        app_running = True
except:
    pass

result = {
    "report": report_info,
    "history": history_info,
    "app_running": app_running,
    "timestamp": time.time(),
    "final_screenshot": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="