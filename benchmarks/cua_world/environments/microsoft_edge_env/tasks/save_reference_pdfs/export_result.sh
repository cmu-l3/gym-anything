#!/bin/bash
# export_result.sh - Post-task hook for save_reference_pdfs task

echo "=== Exporting save_reference_pdfs results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect Data
# Use Python to robustly collect file stats and history without fragile bash parsing
python3 << 'PYEOF'
import json
import os
import sqlite3
import shutil
import tempfile
import time

# Configuration
TASK_START_FILE = "/tmp/task_start_time.txt"
TARGET_DIR = "/home/ga/Documents/Workshop_Materials"
HISTORY_DB = "/home/ga/.config/microsoft-edge/Default/History"
OUTPUT_JSON = "/tmp/task_result.json"

# Get task start time
try:
    with open(TASK_START_FILE, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

result = {
    "task_start": task_start,
    "directory_exists": False,
    "files": {},
    "readme": {
        "exists": False,
        "content": "",
        "created_during_task": False
    },
    "history": {
        "visits": []
    }
}

# Check Directory
if os.path.isdir(TARGET_DIR):
    result["directory_exists"] = True
    
    # Check PDF Files
    expected_pdfs = ["blooms_taxonomy.pdf", "constructivism.pdf", "differentiated_instruction.pdf"]
    
    for filename in expected_pdfs:
        filepath = os.path.join(TARGET_DIR, filename)
        file_info = {
            "exists": False,
            "size": 0,
            "mtime": 0,
            "created_during_task": False,
            "is_valid_pdf": False
        }
        
        if os.path.isfile(filepath):
            file_info["exists"] = True
            stat = os.stat(filepath)
            file_info["size"] = stat.st_size
            file_info["mtime"] = int(stat.st_mtime)
            file_info["created_during_task"] = file_info["mtime"] >= task_start
            
            # Check magic bytes for PDF (%PDF)
            try:
                with open(filepath, 'rb') as f:
                    header = f.read(4)
                    if header == b'%PDF':
                        file_info["is_valid_pdf"] = True
            except:
                pass
                
        result["files"][filename] = file_info

    # Check README
    readme_path = os.path.join(TARGET_DIR, "README.txt")
    if os.path.isfile(readme_path):
        result["readme"]["exists"] = True
        stat = os.stat(readme_path)
        result["readme"]["created_during_task"] = int(stat.st_mtime) >= task_start
        try:
            with open(readme_path, 'r', errors='ignore') as f:
                result["readme"]["content"] = f.read()
        except:
            pass

# Check Browser History
# Copy DB to temp to avoid locks
if os.path.exists(HISTORY_DB):
    temp_db = tempfile.mktemp()
    try:
        shutil.copy2(HISTORY_DB, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Query for wikipedia visits
        cursor.execute("SELECT url, title, last_visit_time FROM urls WHERE url LIKE '%wikipedia.org%'")
        rows = cursor.fetchall()
        
        for row in rows:
            result["history"]["visits"].append({
                "url": row[0],
                "title": row[1]
            })
            
        conn.close()
    except Exception as e:
        print(f"Error checking history: {e}")
    finally:
        if os.path.exists(temp_db):
            os.unlink(temp_db)

# Save result
with open(OUTPUT_JSON, 'w') as f:
    json.dump(result, f, indent=2)
    
print(f"Result saved to {OUTPUT_JSON}")
PYEOF

echo "=== Export Complete ==="