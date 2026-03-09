#!/bin/bash
echo "=== Exporting export_landmark_slices result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png

# Analyze results using Python
python3 << 'PYEOF'
import os
import json
import struct
import time

# configuration
task_start_time = 0
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        task_start_time = int(f.read().strip())
except:
    pass

files_to_check = [
    {"key": "axial", "path": "/home/ga/Documents/axial_orbits.png"},
    {"key": "sagittal", "path": "/home/ga/Documents/sagittal_midline.png"},
    {"key": "coronal", "path": "/home/ga/Documents/coronal_petrous.png"}
]

result = {
    "files": {},
    "task_start_time": task_start_time,
    "timestamp": time.time()
}

for item in files_to_check:
    key = item["key"]
    path = item["path"]
    
    file_info = {
        "exists": False,
        "valid_png": False,
        "size_bytes": 0,
        "created_during_task": False,
        "path": path
    }
    
    if os.path.isfile(path):
        file_info["exists"] = True
        stats = os.stat(path)
        file_info["size_bytes"] = stats.st_size
        file_info["mtime"] = stats.st_mtime
        
        # Anti-gaming: Check if created/modified after task start
        if stats.st_mtime > task_start_time:
            file_info["created_during_task"] = True
            
        # Check PNG magic bytes
        try:
            with open(path, "rb") as f:
                header = f.read(8)
                if header == b"\x89PNG\r\n\x1a\n":
                    file_info["valid_png"] = True
        except:
            pass
            
    result["files"][key] = file_info

with open("/tmp/export_landmark_slices_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="