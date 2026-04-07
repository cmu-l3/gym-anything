#!/bin/bash
# export_result.sh - Export script for Browser Performance Diagnostic
# Collects: Report content, Browser History, Preferences state

echo "=== Exporting Browser Performance Diagnostic Result ==="

REPORT_PATH="/home/ga/Desktop/performance_report.txt"
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
START_TS_FILE="/tmp/task_start_time.txt"

# 1. Take final screenshot (Trajectory Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure Preferences are flushed to disk
# Edge writes prefs on exit or periodically; killing ensures we read latest state
echo "Stopping Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 3. Use Python to gather all verification data into a single JSON
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import time
import re

# Load start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        start_ts = int(f.read().strip())
except:
    start_ts = 0

result = {
    "task_start_ts": start_ts,
    "timestamp": time.time(),
    "report": {
        "exists": False,
        "content": "",
        "modified_ts": 0
    },
    "history": [],
    "preferences": {}
}

# --- CHECK REPORT FILE ---
report_path = "/home/ga/Desktop/performance_report.txt"
if os.path.exists(report_path):
    result["report"]["exists"] = True
    result["report"]["modified_ts"] = os.path.getmtime(report_path)
    try:
        with open(report_path, "r", errors="ignore") as f:
            result["report"]["content"] = f.read()
    except Exception as e:
        result["report"]["error"] = str(e)

# --- CHECK BROWSER HISTORY ---
history_db = "/home/ga/.config/microsoft-edge/Default/History"
temp_db = "/tmp/history_export.sqlite"

if os.path.exists(history_db):
    try:
        # Copy to temp to avoid locks
        shutil.copy2(history_db, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Edge/Chromium time is microseconds since 1601-01-01
        # To get Unix seconds: (webkit_time / 1000000) - 11644473600
        # We only care about visits AFTER task start
        
        webkit_start = (start_ts + 11644473600) * 1000000
        
        query = f"""
            SELECT url, title, last_visit_time 
            FROM urls 
            WHERE last_visit_time > {webkit_start}
        """
        cursor.execute(query)
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
        if os.path.exists(temp_db):
            os.remove(temp_db)

# --- CHECK PREFERENCES ---
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, "r") as f:
            prefs = json.load(f)
            
        # Extract relevant sections safely
        browser = prefs.get("browser", {})
        
        result["preferences"] = {
            "sleeping_tabs": browser.get("sleeping_tabs", {}),
            "startup_boost": browser.get("startup_boost", {})
        }
    except Exception as e:
        result["preferences_error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export verification data complete.")
PYEOF

# 4. Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json