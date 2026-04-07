#!/bin/bash
set -e

echo "=== Exporting PubMed Archival Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Use Python to gather file system and history evidence robustly
python3 << 'PYEOF'
import json
import os
import re
import sqlite3
import shutil
import time
import glob

# Constants
TARGET_DIR = "/home/ga/Documents/JournalClub"
TASK_START_FILE = "/tmp/task_start_time.txt"
HISTORY_DB = "/home/ga/.config/microsoft-edge/Default/History"
RESULT_FILE = "/tmp/task_result.json"

result = {
    "files": [],
    "history_found": False,
    "directory_exists": False,
    "task_start_ts": 0,
    "timestamp": time.time()
}

# Get task start time
try:
    with open(TASK_START_FILE, 'r') as f:
        result["task_start_ts"] = int(f.read().strip())
except Exception as e:
    print(f"Error reading start time: {e}")

# Check Directory
if os.path.exists(TARGET_DIR) and os.path.isdir(TARGET_DIR):
    result["directory_exists"] = True
    
    # List files and check metadata
    for filename in os.listdir(TARGET_DIR):
        filepath = os.path.join(TARGET_DIR, filename)
        if os.path.isfile(filepath):
            stat = os.stat(filepath)
            
            # Check if it's a valid PDF (magic bytes)
            is_pdf = False
            try:
                with open(filepath, 'rb') as f:
                    header = f.read(4)
                    if header.startswith(b'%PDF'):
                        is_pdf = True
            except:
                pass

            result["files"].append({
                "name": filename,
                "size": stat.st_size,
                "mtime": stat.st_mtime,
                "is_pdf_content": is_pdf,
                "created_after_start": stat.st_mtime > result["task_start_ts"]
            })

# Check Browser History for PubMed visits
if os.path.exists(HISTORY_DB):
    try:
        # Copy DB to avoid locks
        temp_db = "/tmp/history_check.sqlite"
        shutil.copy2(HISTORY_DB, temp_db)
        
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Look for visits to pubmed or pmc after task start
        # Edge/Chrome time is microseconds since 1601-01-01
        # To simplify, we just check existence, anti-gaming relies on file timestamps mostly
        cursor.execute("SELECT url FROM urls WHERE url LIKE '%ncbi.nlm.nih.gov%'")
        rows = cursor.fetchall()
        
        if rows:
            result["history_found"] = True
            
        conn.close()
        os.remove(temp_db)
    except Exception as e:
        print(f"Error checking history: {e}")

# Write result
with open(RESULT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic finished.")
PYEOF

# 3. Secure the output file
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json