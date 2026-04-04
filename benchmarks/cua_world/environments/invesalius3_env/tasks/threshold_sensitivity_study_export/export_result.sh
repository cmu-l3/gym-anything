#!/bin/bash
echo "=== Exporting threshold_sensitivity_study_export result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Analyze output files using Python
# We check existence, binary STL validity, triangle counts, and timestamps
python3 << 'PYEOF'
import struct, os, json, time

files_to_check = [
    {"path": "/home/ga/Documents/skull_200HU.stl", "label": "200HU"},
    {"path": "/home/ga/Documents/skull_400HU.stl", "label": "400HU"},
    {"path": "/home/ga/Documents/skull_600HU.stl", "label": "600HU"}
]

# Get task start time
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

result = {
    "files": {},
    "task_start_time": task_start_time,
    "timestamp_check_passed": True
}

for item in files_to_check:
    fpath = item["path"]
    label = item["label"]
    file_info = {
        "exists": False,
        "size": 0,
        "is_binary_stl": False,
        "triangle_count": 0,
        "mtime": 0,
        "created_during_task": False
    }
    
    if os.path.isfile(fpath):
        file_info["exists"] = True
        file_info["size"] = os.path.getsize(fpath)
        file_info["mtime"] = int(os.path.getmtime(fpath))
        
        # Check timestamp against task start
        if file_info["mtime"] >= task_start_time:
            file_info["created_during_task"] = True
        else:
            result["timestamp_check_passed"] = False
        
        # Check Binary STL Header
        # Header is 80 bytes, then 4 bytes (uint32) for triangle count
        if file_info["size"] >= 84:
            try:
                with open(fpath, "rb") as f:
                    header = f.read(80)
                    count_bytes = f.read(4)
                    if len(count_bytes) == 4:
                        tri_count = struct.unpack("<I", count_bytes)[0]
                        
                        # Validate file size matches triangle count formula
                        # Expected size = 80 + 4 + (50 * triangle_count)
                        expected_size = 84 + (50 * tri_count)
                        
                        # Allow small buffer for potential footer/metadata (rare in standard STL but possible)
                        if abs(file_info["size"] - expected_size) < 1024:
                            file_info["is_binary_stl"] = True
                            file_info["triangle_count"] = tri_count
            except Exception as e:
                file_info["error"] = str(e)
                
    result["files"][label] = file_info

with open("/tmp/threshold_study_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="