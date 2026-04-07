#!/bin/bash
# Export script for Tariff HTS Research task
set -e

TASK_NAME="tariff_hts_research"
REPORT_FILE="/home/ga/Desktop/tariff_classification.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
RESULT_JSON="/tmp/task_result.json"

echo "=== Exporting results for ${TASK_NAME} ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_final.png 2>/dev/null || true

# 2. Python script to gather all verification data
# This handles SQLite locking, file parsing, and logic in one robust place
python3 << 'PYEOF'
import json, os, re, shutil, sqlite3, tempfile, glob, time

# -- Load configuration --
report_path = "/home/ga/Desktop/tariff_classification.txt"
downloads_dir = "/home/ga/Downloads"
start_ts_path = "/tmp/task_start_ts_tariff_hts_research.txt"
baseline_path = "/tmp/history_baseline_counts.json"
result_path = "/tmp/task_result.json"

# -- Get Task Start Time --
try:
    with open(start_ts_path, 'r') as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

# -- Analyze Report File --
report_data = {
    "exists": False,
    "size": 0,
    "modified_after_start": False,
    "content": ""
}

if os.path.exists(report_path):
    stats = os.stat(report_path)
    report_data["exists"] = True
    report_data["size"] = stats.st_size
    report_data["modified_after_start"] = stats.st_mtime > task_start_time
    
    try:
        with open(report_path, 'r', errors='ignore') as f:
            report_data["content"] = f.read()
    except Exception as e:
        report_data["content"] = f"Error reading file: {e}"

# -- Analyze Browser History --
history_data = {
    "usitc_visits": 0,
    "cbp_visits": 0,
    "new_usitc_activity": False,
    "new_cbp_activity": False
}

history_db = "/home/ga/.config/microsoft-edge/Default/History"
if os.path.exists(history_db):
    try:
        # Copy DB to temp file to avoid locks
        tmp_db = tempfile.mktemp(suffix=".sqlite")
        shutil.copy2(history_db, tmp_db)
        
        conn = sqlite3.connect(tmp_db)
        cur = conn.cursor()
        
        # Get current counts
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%usitc.gov%'")
        history_data["usitc_visits"] = cur.fetchone()[0] or 0
        
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%cbp.gov%'")
        history_data["cbp_visits"] = cur.fetchone()[0] or 0
        
        conn.close()
        os.remove(tmp_db)
    except Exception as e:
        print(f"History check error: {e}")

# Compare with baseline
try:
    with open(baseline_path, 'r') as f:
        baseline = json.load(f)
        history_data["new_usitc_activity"] = history_data["usitc_visits"] > baseline.get("usitc_count", 0)
        history_data["new_cbp_activity"] = history_data["cbp_visits"] > baseline.get("cbp_count", 0)
except:
    # If no baseline, assume any visit is valid (fallback)
    pass

# -- Analyze Downloads --
# Look for files downloaded *during* the task from government sources
download_data = {
    "has_new_gov_download": False,
    "files": []
}

if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            if mtime > task_start_time:
                # It's a new file. Check if it looks like a government doc 
                # (We rely on history DB for source URL usually, but file existence is a strong signal)
                # HTS chapters often named "chapterX.pdf" or similar
                download_data["files"].append(fname)
                download_data["has_new_gov_download"] = True 

# -- Compile Final Result --
result = {
    "task_start_time": task_start_time,
    "report": report_data,
    "history": history_data,
    "downloads": download_data
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Export verification data complete.")
PYEOF

# 3. Secure the result file
chmod 666 "$RESULT_JSON"

echo "=== Export complete ==="