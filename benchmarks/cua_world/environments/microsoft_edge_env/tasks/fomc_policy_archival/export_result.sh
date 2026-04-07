#!/bin/bash
echo "=== Exporting FOMC Policy Archival Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TARGET_DIR="/home/ga/Documents/FOMC_Policy"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare Python script to extract robust results
cat > /tmp/extract_results.py << 'PYEOF'
import json
import os
import glob
import sqlite3
import shutil
import time

target_dir = "/home/ga/Documents/FOMC_Policy"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

result = {
    "task_start": task_start,
    "target_dir_exists": os.path.isdir(target_dir),
    "files": {},
    "history_found": False
}

# 1. Analyze Files
if result["target_dir_exists"]:
    for filename in ["statement.pdf", "implementation_note.pdf", "metadata.txt", "summary_text.txt"]:
        filepath = os.path.join(target_dir, filename)
        file_info = {
            "exists": False,
            "size": 0,
            "created_during_task": False,
            "content_preview": ""
        }
        
        if os.path.exists(filepath):
            file_info["exists"] = True
            stat = os.stat(filepath)
            file_info["size"] = stat.st_size
            # Check modification time against task start
            file_info["created_during_task"] = stat.st_mtime > task_start
            
            # Read text content for preview
            if filename.endswith(".txt"):
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                        file_info["content_preview"] = f.read(1000) # First 1000 chars
                except:
                    pass
            # Check PDF magic bytes
            elif filename.endswith(".pdf"):
                try:
                    with open(filepath, 'rb') as f:
                        header = f.read(4)
                        file_info["is_pdf"] = (header == b'%PDF')
                except:
                    file_info["is_pdf"] = False
                    
        result["files"][filename] = file_info

# 2. Analyze Browser History
history_db = "/home/ga/.config/microsoft-edge/Default/History"
if os.path.exists(history_db):
    try:
        # Copy to temp file to avoid locking issues
        shutil.copy2(history_db, "/tmp/history_copy.sqlite")
        conn = sqlite3.connect("/tmp/history_copy.sqlite")
        cursor = conn.cursor()
        
        # Check for visits to federalreserve.gov
        cursor.execute("SELECT count(*) FROM urls WHERE url LIKE '%federalreserve.gov%'")
        count = cursor.fetchone()[0]
        result["history_found"] = count > 0
        
        # Get list of visited URLs for debugging
        cursor.execute("SELECT url FROM urls WHERE url LIKE '%federalreserve.gov%' ORDER BY last_visit_time DESC LIMIT 5")
        result["recent_fed_urls"] = [row[0] for row in cursor.fetchall()]
        
        conn.close()
    except Exception as e:
        result["history_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Run extraction and save to JSON
python3 /tmp/extract_results.py > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result export complete."
cat /tmp/task_result.json