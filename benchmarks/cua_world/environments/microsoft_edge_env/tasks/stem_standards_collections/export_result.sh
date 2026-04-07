#!/bin/bash
# Export script for STEM Standards Research task
# Verifies file creation, history visits, and Collections modification.

echo "=== Exporting STEM Standards Collections Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Run Python export logic
python3 << 'PYEOF'
import json
import os
import re
import shutil
import sqlite3
import tempfile
import time

# Load task start timestamp
try:
    with open("/tmp/task_start_ts_stem_standards_collections.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 1. Verify Document Content
doc_path = "/home/ga/Desktop/stem_standards_reference.txt"
doc_result = {
    "exists": False,
    "modified_after_start": False,
    "size": 0,
    "content_check": {
        "ngss": False,
        "common_core": False,
        "iste": False,
        "nces": False
    }
}

if os.path.exists(doc_path):
    stat = os.stat(doc_path)
    doc_result["exists"] = True
    doc_result["size"] = stat.st_size
    doc_result["modified_after_start"] = stat.st_mtime > task_start
    
    try:
        with open(doc_path, "r", errors="ignore") as f:
            content = f.read().lower()
            doc_result["content_check"]["ngss"] = "nextgenscience" in content or "ngss" in content
            doc_result["content_check"]["common_core"] = "corestandards" in content or "common core" in content
            doc_result["content_check"]["iste"] = "iste" in content
            doc_result["content_check"]["nces"] = "nces" in content or "national center for education statistics" in content
    except Exception as e:
        print(f"Error reading document: {e}")

# 2. Verify History (Visits to target domains)
history_path = "/home/ga/.config/microsoft-edge/Default/History"
history_result = {
    "nextgenscience.org": False,
    "corestandards.org": False,
    "iste.org": False,
    "nces.ed.gov": False,
    "visit_count": 0
}

if os.path.exists(history_path):
    # Copy to temp file to avoid locking
    tmp_hist = tempfile.mktemp(suffix=".sqlite")
    try:
        shutil.copy2(history_path, tmp_hist)
        conn = sqlite3.connect(tmp_hist)
        cursor = conn.cursor()
        
        # Check specific domains
        domains = {
            "nextgenscience.org": ["nextgenscience.org"],
            "corestandards.org": ["corestandards.org"],
            "iste.org": ["iste.org"],
            "nces.ed.gov": ["nces.ed.gov"]
        }
        
        total_visits = 0
        for key, patterns in domains.items():
            found = False
            for pattern in patterns:
                cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE ?", (f"%{pattern}%",))
                count = cursor.fetchone()[0]
                if count > 0:
                    found = True
                    total_visits += 1
            history_result[key] = found
            
        history_result["visit_count"] = total_visits
        conn.close()
    except Exception as e:
        print(f"Error querying history: {e}")
    finally:
        if os.path.exists(tmp_hist):
            os.remove(tmp_hist)

# 3. Verify Collections Usage (File System Check)
# Edge Collections are stored in 'Collections' directory. 
# We check if this directory or files inside were modified during task.
collections_dir = "/home/ga/.config/microsoft-edge/Default/Collections"
collections_result = {
    "modified": False,
    "timestamp": 0
}

if os.path.exists(collections_dir):
    # Check directory mtime
    dir_mtime = os.stat(collections_dir).st_mtime
    latest_mtime = dir_mtime
    
    # Check children (recursively shallow)
    for root, dirs, files in os.walk(collections_dir):
        for name in files:
            try:
                mtime = os.stat(os.path.join(root, name)).st_mtime
                if mtime > latest_mtime:
                    latest_mtime = mtime
            except:
                pass
                
    collections_result["timestamp"] = latest_mtime
    collections_result["modified"] = latest_mtime > task_start

# Combine Results
final_result = {
    "task_start": task_start,
    "document": doc_result,
    "history": history_result,
    "collections": collections_result
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_result, f, indent=2)

print(json.dumps(final_result, indent=2))
PYEOF

echo "=== Export Complete ==="