#!/bin/bash
echo "=== Exporting anatomical_views_panoramic result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze output files using Python
# We check existence, size, valid PNG header, timestamp, and calculate hash to ensure uniqueness
python3 << 'PYEOF'
import os
import json
import hashlib
import time

files_to_check = [
    {"key": "frontalis", "path": "/home/ga/Documents/norma_frontalis.png"},
    {"key": "lateralis", "path": "/home/ga/Documents/norma_lateralis.png"},
    {"key": "basilaris", "path": "/home/ga/Documents/norma_basilaris.png"}
]

task_start = int(os.environ.get('TASK_START', 0))
result = {
    "files": {},
    "distinct_files": True,
    "timestamp_valid": True
}

hashes = []

for item in files_to_check:
    key = item["key"]
    path = item["path"]
    file_info = {
        "exists": False,
        "valid_png": False,
        "size_bytes": 0,
        "created_during_task": False
    }
    
    if os.path.isfile(path):
        file_info["exists"] = True
        size = os.path.getsize(path)
        file_info["size_bytes"] = size
        mtime = os.path.getmtime(path)
        
        # Check if created during task (allow 2s buffer for clock skew)
        if mtime >= (task_start - 2):
            file_info["created_during_task"] = True
        else:
            result["timestamp_valid"] = False
            
        # Check PNG magic bytes
        try:
            with open(path, "rb") as f:
                header = f.read(8)
                if header == b"\x89PNG\r\n\x1a\n":
                    file_info["valid_png"] = True
                
                # Calculate hash for uniqueness check
                f.seek(0)
                file_hash = hashlib.md5(f.read()).hexdigest()
                hashes.append(file_hash)
        except Exception:
            pass
            
    result["files"][key] = file_info

# Check uniqueness (anti-gaming: did they just copy the same file 3 times?)
# Only strictly enforce if we have at least 2 files
if len(hashes) > 1:
    if len(hashes) != len(set(hashes)):
        result["distinct_files"] = False

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="