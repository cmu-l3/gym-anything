#!/bin/bash
# Export script for Accessibility Terminal Config task

echo "=== Exporting Accessibility Config Result ==="

# Source shared utilities
source /workspace/utils/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot (Visual evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure Preferences are flushed to disk
# Chromium browsers often keep prefs in memory; killing ensures we read the latest state.
echo "Stopping Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
sleep 3

# 3. Use Python to extract all verification data
python3 << 'PYEOF'
import json
import os
import sqlite3
import shutil
import time
import tempfile

# Paths
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
history_db = "/home/ga/.config/microsoft-edge/Default/History"
doc_path = "/home/ga/Desktop/accessibility_config_guide.txt"
start_ts_path = "/tmp/task_start_ts.txt"

# Load start time
try:
    with open(start_ts_path, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Data container
result = {
    "task_start": task_start,
    "timestamp": time.time(),
    "prefs": {},
    "history": [],
    "doc": {
        "exists": False,
        "content": "",
        "modified_after_start": False
    }
}

# --- EXTRACT PREFERENCES ---
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
            
            # Extract relevant accessibility settings
            webprefs = prefs.get("webkit", {}).get("webprefs", {})
            result["prefs"]["default_font_size"] = webprefs.get("default_font_size", 16)
            result["prefs"]["minimum_font_size"] = webprefs.get("minimum_font_size", 0)
            
            # Extract homepage settings
            result["prefs"]["homepage"] = prefs.get("homepage", "")
            result["prefs"]["show_home_button"] = prefs.get("browser", {}).get("show_home_button", False)
            
            # Extract startup settings
            # restore_on_startup: 4 = Open specific pages, 1 = Restore, 5 = New Tab
            result["prefs"]["restore_on_startup"] = prefs.get("session", {}).get("restore_on_startup", 0)
            result["prefs"]["startup_urls"] = prefs.get("session", {}).get("startup_urls", [])
            
    except Exception as e:
        result["prefs_error"] = str(e)

# --- EXTRACT HISTORY ---
# Copy DB to temp to avoid locks
if os.path.exists(history_db):
    tmp_db = tempfile.mktemp()
    try:
        shutil.copy2(history_db, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        
        # Check for visits to required sites AFTER task start
        # Edge history time is microseconds since 1601-01-01
        # Convert unix timestamp to Webkit format
        webkit_start_time = (task_start + 11644473600) * 1000000
        
        query = """
            SELECT url, title, last_visit_time 
            FROM urls 
            WHERE (url LIKE '%usa.gov%' OR url LIKE '%ssa.gov%')
            AND last_visit_time > ?
        """
        cursor.execute(query, (webkit_start_time,))
        rows = cursor.fetchall()
        
        for row in rows:
            result["history"].append({
                "url": row[0],
                "title": row[1]
            })
            
        conn.close()
    except Exception as e:
        result["history_error"] = str(e)
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)

# --- EXTRACT DOCUMENT ---
if os.path.exists(doc_path):
    result["doc"]["exists"] = True
    stat = os.stat(doc_path)
    result["doc"]["size"] = stat.st_size
    result["doc"]["modified_after_start"] = stat.st_mtime > task_start
    try:
        with open(doc_path, 'r', errors='replace') as f:
            result["doc"]["content"] = f.read(2048) # Read first 2KB
    except:
        result["doc"]["content"] = "[Read Error]"

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to accessible location if needed (though /tmp is fine)
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="