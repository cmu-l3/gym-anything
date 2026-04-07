#!/bin/bash
# Export script for USDA Crop Market Research task

echo "=== Exporting Results ==="

# Source utils
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python for robust verification data extraction
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import tempfile
import time

# --- CONFIG ---
TASK_START_FILE = "/tmp/task_start_ts.txt"
BRIEF_PATH = "/home/ga/Desktop/planting_brief.txt"
DOWNLOADS_DIR = "/home/ga/Downloads"
HISTORY_DB = "/home/ga/.config/microsoft-edge/Default/History"
RESULT_FILE = "/tmp/task_result.json"

# --- HELPERS ---
def get_task_start():
    try:
        with open(TASK_START_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return 0

def check_history(start_time):
    """Query Edge history for USDA visits after task start."""
    visits = []
    if not os.path.exists(HISTORY_DB):
        return visits
    
    # Copy DB to avoid locks
    tmp_db = tempfile.mktemp(suffix=".sqlite")
    try:
        shutil.copy2(HISTORY_DB, tmp_db)
        conn = sqlite3.connect(tmp_db)
        # SQLite time is nanoseconds or microseconds depending on browser version, 
        # but often it's WebKit time (microseconds since 1601).
        # However, simpler check is just URL presence since we cleared/killed browser.
        # Ideally we check timestamp, but for simplicity in this env we check all history 
        # assuming setup didn't pre-load these specific USDA pages.
        cursor = conn.cursor()
        cursor.execute("SELECT url, title FROM urls")
        for row in cursor.fetchall():
            visits.append({"url": row[0], "title": row[1]})
        conn.close()
    except Exception as e:
        print(f"Error reading history: {e}")
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)
    return visits

def check_downloads(start_time):
    """Check for files in Downloads folder modified after start_time."""
    downloaded_files = []
    if not os.path.exists(DOWNLOADS_DIR):
        return downloaded_files
        
    for f in os.listdir(DOWNLOADS_DIR):
        fpath = os.path.join(DOWNLOADS_DIR, f)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            if mtime > start_time:
                downloaded_files.append({
                    "name": f,
                    "size": os.path.getsize(fpath),
                    "mtime": mtime
                })
    return downloaded_files

# --- MAIN LOGIC ---
task_start = get_task_start()

# 1. Analyze Brief
brief_exists = False
brief_content = ""
brief_mtime = 0

if os.path.exists(BRIEF_PATH):
    brief_exists = True
    brief_mtime = os.path.getmtime(BRIEF_PATH)
    try:
        with open(BRIEF_PATH, 'r', errors='ignore') as f:
            brief_content = f.read()
    except:
        brief_content = "[Error reading file]"

# 2. Analyze History
history_data = check_history(task_start)
usda_domains = ["usda.gov", "ers.usda.gov", "nass.usda.gov", "marketnews.usda.gov", "fas.usda.gov"]
usda_visits = [
    v for v in history_data 
    if any(d in v['url'] for d in usda_domains)
]

# 3. Analyze Downloads
downloads = check_downloads(task_start)

# Compile Result
result = {
    "task_start": task_start,
    "brief": {
        "exists": brief_exists,
        "mtime": brief_mtime,
        "created_during_task": brief_mtime > task_start,
        "content_length": len(brief_content),
        # We don't save full content to JSON if it's huge, but for text files it's fine
        "content_snippet": brief_content[:5000] 
    },
    "history": {
        "total_visits": len(history_data),
        "usda_visits_count": len(usda_visits),
        "usda_urls": [v['url'] for v in usda_visits[:10]] # limit output size
    },
    "downloads": {
        "count": len(downloads),
        "files": downloads
    },
    "screenshot_path": "/tmp/task_end_screenshot.png"
}

with open(RESULT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "Result saved to /tmp/task_result.json"