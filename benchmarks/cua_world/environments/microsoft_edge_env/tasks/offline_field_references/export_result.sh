#!/bin/bash
# export_result.sh for offline_field_references
set -e

echo "=== Exporting Offline Field References Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Close Edge (to ensure history is flushed to disk)
echo "Closing Edge to flush history..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Collect Data using Python
# We use Python to robustly check file metadata, history, and content
python3 << 'PYEOF'
import os
import json
import sqlite3
import shutil
import time
import glob

# Constants
TARGET_DIR = "/home/ga/Documents/offline_references"
INDEX_FILE = os.path.join(TARGET_DIR, "index.txt")
TASK_START_FILE = "/tmp/task_start_time.txt"
BASELINE_HISTORY = "/tmp/history_baseline.json"
HISTORY_DB = "/home/ga/.config/microsoft-edge/Default/History"
OUTPUT_JSON = "/tmp/task_result.json"

result = {
    "directory_exists": False,
    "html_files": [],
    "index_file": {
        "exists": False,
        "size": 0,
        "content": "",
        "modified_after_start": False
    },
    "history_visits": {},
    "task_start_time": 0,
    "timestamp": time.time()
}

# Load task start time
try:
    with open(TASK_START_FILE, 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except:
    result["task_start_time"] = 0

# Check Directory and Files
if os.path.isdir(TARGET_DIR):
    result["directory_exists"] = True
    
    # List all HTML files
    # patterns to match: .html, .htm
    files = glob.glob(os.path.join(TARGET_DIR, "*.html")) + glob.glob(os.path.join(TARGET_DIR, "*.htm"))
    
    for fpath in files:
        stats = os.stat(fpath)
        result["html_files"].append({
            "name": os.path.basename(fpath),
            "size": stats.st_size,
            "mtime": stats.st_mtime,
            "created_during_task": stats.st_mtime > result["task_start_time"]
        })

    # Check Index File
    if os.path.isfile(INDEX_FILE):
        stats = os.stat(INDEX_FILE)
        result["index_file"]["exists"] = True
        result["index_file"]["size"] = stats.st_size
        result["index_file"]["modified_after_start"] = stats.st_mtime > result["task_start_time"]
        try:
            with open(INDEX_FILE, 'r', errors='ignore') as f:
                result["index_file"]["content"] = f.read()
        except:
            result["index_file"]["content"] = "[Error reading content]"

# Check Browser History
domains = ["usda.gov", "epa.gov", "nass.usda.gov"]
baseline_counts = {d: 0 for d in domains}

# Load baseline
if os.path.exists(BASELINE_HISTORY):
    try:
        with open(BASELINE_HISTORY, 'r') as f:
            baseline_counts = json.load(f)
    except:
        pass

# Query current history
if os.path.exists(HISTORY_DB):
    try:
        shutil.copy2(HISTORY_DB, "/tmp/history_final.db")
        conn = sqlite3.connect("/tmp/history_final.db")
        cursor = conn.cursor()
        
        for domain in domains:
            query = f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%'"
            cursor.execute(query)
            current_count = cursor.fetchone()[0]
            
            # Determine if visited during task (count increased)
            # Note: This is a simple heuristic. Timestamp checking in DB is better but schema varies.
            # Count increase is reliable for "new visits".
            visited = current_count > baseline_counts.get(domain, 0)
            result["history_visits"][domain] = {
                "visited": visited,
                "initial_count": baseline_counts.get(domain, 0),
                "final_count": current_count
            }
        
        conn.close()
        os.remove("/tmp/history_final.db")
    except Exception as e:
        print(f"Error checking history: {e}")
        # Default to False if error
        for domain in domains:
            if domain not in result["history_visits"]:
                result["history_visits"][domain] = {"visited": False, "error": str(e)}

# Save Result
with open(OUTPUT_JSON, 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to", OUTPUT_JSON)
PYEOF

# 4. Set permissions for the result file so verification script can read it
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="