#!/bin/bash
echo "=== Exporting multi_tissue_stl_export result ==="

source /workspace/scripts/task_utils.sh

# Paths
BONE_FILE="/home/ga/Documents/bone_model.stl"
SKIN_FILE="/home/ga/Documents/skin_model.stl"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Capture Final Visual State
take_screenshot /tmp/task_end.png

# 2. Analyze Output Files using Python
# We use Python to robustly parse the binary STL header and calculate stats
python3 << PYEOF
import struct
import os
import json
import hashlib

def get_file_info(path, start_time):
    info = {
        "exists": False,
        "size_bytes": 0,
        "is_binary_stl": False,
        "triangle_count": 0,
        "created_during_task": False,
        "md5": ""
    }
    
    if os.path.isfile(path):
        info["exists"] = True
        stats = os.stat(path)
        info["size_bytes"] = stats.st_size
        
        # Check creation/modification time
        if stats.st_mtime > float(start_time):
            info["created_during_task"] = True
            
        # Calculate MD5 for comparison
        try:
            with open(path, "rb") as f:
                data = f.read()
                info["md5"] = hashlib.md5(data).hexdigest()
                
            # Parse Binary STL
            # Header: 80 bytes
            # Count: 4 bytes (uint32)
            # Triangles: 50 bytes each
            if info["size_bytes"] >= 84:
                with open(path, "rb") as f:
                    _ = f.read(80) # header
                    count_bytes = f.read(4)
                    if len(count_bytes) == 4:
                        count = struct.unpack("<I", count_bytes)[0]
                        expected_size = 84 + (count * 50)
                        # Allow slight difference for footer or padding, but standard is exact
                        if abs(expected_size - info["size_bytes"]) <= 1024: 
                            info["is_binary_stl"] = True
                            info["triangle_count"] = count
        except Exception as e:
            info["error"] = str(e)
            
    return info

bone_path = "$BONE_FILE"
skin_path = "$SKIN_FILE"
start_time = $TASK_START

result = {
    "bone_stl": get_file_info(bone_path, start_time),
    "skin_stl": get_file_info(skin_path, start_time),
    "files_are_distinct": False
}

# Cross-file verification
if result["bone_stl"]["exists"] and result["skin_stl"]["exists"]:
    # Check if files are binary identical
    if result["bone_stl"]["md5"] != result["skin_stl"]["md5"]:
        # Check if triangle counts are significantly different (optional logic handled in verifier usually, 
        # but good to flag here)
        result["files_are_distinct"] = True

# Write result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 3. Permissions fix for verifier access
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="