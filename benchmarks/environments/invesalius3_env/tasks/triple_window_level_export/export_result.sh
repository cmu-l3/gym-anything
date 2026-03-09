#!/bin/bash
# Export result for triple_window_level_export task

echo "=== Exporting results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the desktop
take_screenshot /tmp/task_end.png

# Paths
BONE_PATH="/home/ga/Documents/bone_window.png"
BRAIN_PATH="/home/ga/Documents/brain_window.png"
SOFT_PATH="/home/ga/Documents/soft_tissue_window.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to analyze files (checksums, magic bytes, timestamps)
python3 << PYEOF
import os
import json
import hashlib
import struct

files = {
    "bone": "$BONE_PATH",
    "brain": "$BRAIN_PATH",
    "soft_tissue": "$SOFT_PATH"
}
task_start = int("$TASK_START")

result = {
    "files": {},
    "all_exist": False,
    "distinct_content": False
}

md5_hashes = []
existing_count = 0

for key, path in files.items():
    file_info = {
        "exists": False,
        "size_bytes": 0,
        "is_png": False,
        "created_after_start": False,
        "md5": None
    }
    
    if os.path.isfile(path):
        file_info["exists"] = True
        existing_count += 1
        
        # Size
        stat = os.stat(path)
        file_info["size_bytes"] = stat.st_size
        
        # Timestamp check
        if stat.st_mtime > task_start:
            file_info["created_after_start"] = True
            
        # PNG Magic check
        try:
            with open(path, "rb") as f:
                header = f.read(8)
                if header == b"\x89PNG\r\n\x1a\n":
                    file_info["is_png"] = True
                
                # MD5 (rewind)
                f.seek(0)
                file_hash = hashlib.md5(f.read()).hexdigest()
                file_info["md5"] = file_hash
                md5_hashes.append(file_hash)
        except Exception:
            pass
            
    result["files"][key] = file_info

result["all_exist"] = (existing_count == 3)

# Check distinctness
if len(md5_hashes) == 3:
    # Set of hashes should have length 3 if all are unique
    if len(set(md5_hashes)) == 3:
        result["distinct_content"] = True
elif len(md5_hashes) > 0 and len(md5_hashes) == existing_count:
     # If they managed to create fewer files, check if those at least are distinct
     if len(set(md5_hashes)) == len(md5_hashes):
         result["distinct_content"] = True # Partially distinct

with open("/tmp/triple_window_level_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions for the result file
chmod 666 /tmp/triple_window_level_result.json 2>/dev/null || true

echo "=== Export Complete ==="