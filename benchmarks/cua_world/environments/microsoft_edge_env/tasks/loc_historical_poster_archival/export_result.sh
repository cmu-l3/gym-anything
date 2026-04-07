#!/bin/bash
# Export results for LOC Historical Poster Archival task

echo "=== Exporting loc_historical_poster_archival results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python script to analyze filesystem, manifest, and history
# Using python for robust JSON handling and verification logic
python3 << 'PYEOF'
import json
import os
import sqlite3
import shutil
import time

# --- Configuration ---
TARGET_DIR = "/home/ga/Pictures/WPA_Travel"
MANIFEST_FILE = os.path.join(TARGET_DIR, "manifest.json")
TASK_START_FILE = "/tmp/task_start_time.txt"
HISTORY_BASELINE_FILE = "/tmp/history_baseline_count.txt"
RESULT_FILE = "/tmp/task_result.json"

result = {
    "dir_exists": False,
    "image_count": 0,
    "valid_images": [], # List of filenames > 50KB
    "manifest_exists": False,
    "manifest_valid_json": False,
    "manifest_content": [],
    "manifest_keys_check": False,
    "files_in_manifest_exist": False,
    "loc_visits_detected": False,
    "timestamp": time.time()
}

# --- Check Directory & Images ---
if os.path.isdir(TARGET_DIR):
    result["dir_exists"] = True
    files = os.listdir(TARGET_DIR)
    
    for f in files:
        f_path = os.path.join(TARGET_DIR, f)
        if os.path.isfile(f_path):
            # Check extension
            ext = os.path.splitext(f)[1].lower()
            if ext in ['.jpg', '.jpeg']:
                # Check size (filter out thumbnails/empty files)
                size_kb = os.path.getsize(f_path) / 1024
                if size_kb > 50: # Expecting high res > 50KB
                    result["valid_images"].append(f)

    result["image_count"] = len(result["valid_images"])

# --- Check Manifest ---
if os.path.exists(MANIFEST_FILE):
    result["manifest_exists"] = True
    try:
        with open(MANIFEST_FILE, 'r') as f:
            data = json.load(f)
            result["manifest_valid_json"] = True
            
            if isinstance(data, list):
                result["manifest_content"] = data
                
                # Verify keys and file existence
                keys_ok = True
                files_exist = True
                required_keys = ["title", "year", "url", "filename"]
                
                for entry in data:
                    # Check keys
                    if not all(k in entry for k in required_keys):
                        keys_ok = False
                    
                    # Check referenced file exists
                    fname = entry.get("filename")
                    if fname:
                        fpath = os.path.join(TARGET_DIR, fname)
                        if not os.path.exists(fpath):
                            files_exist = False
                    else:
                        files_exist = False # No filename provided
                
                if len(data) > 0:
                    result["manifest_keys_check"] = keys_ok
                    result["files_in_manifest_exist"] = files_exist

    except json.JSONDecodeError:
        result["manifest_valid_json"] = False
    except Exception as e:
        print(f"Error reading manifest: {e}")

# --- Check History ---
history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_count = 0
if os.path.exists(HISTORY_BASELINE_FILE):
    try:
        with open(HISTORY_BASELINE_FILE, 'r') as f:
            baseline_count = int(f.read().strip())
    except:
        pass

if os.path.exists(history_db):
    try:
        shutil.copy2(history_db, "/tmp/history_export.db")
        conn = sqlite3.connect("/tmp/history_export.db")
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%loc.gov%'")
        current_count = cursor.fetchone()[0]
        conn.close()
        os.remove("/tmp/history_export.db")
        
        if current_count > baseline_count:
            result["loc_visits_detected"] = True
    except Exception as e:
        print(f"Error checking history: {e}")

# --- Write Result ---
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 3. Secure output file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="