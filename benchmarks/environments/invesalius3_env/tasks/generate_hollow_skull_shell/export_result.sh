#!/bin/bash
echo "=== Exporting generate_hollow_skull_shell result ==="

source /workspace/scripts/task_utils.sh

# Paths
STL_PATH="/home/ga/Documents/hollow_skull.stl"
PROJ_PATH="/home/ga/Documents/hollow_project.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze output files using Python
python3 << PYEOF
import os
import json
import struct
import tarfile

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "stl_exists": False,
    "stl_size": 0,
    "stl_triangles": 0,
    "stl_is_binary": False,
    "proj_exists": False,
    "proj_mask_count": 0,
    "proj_valid": False
}

stl_path = "$STL_PATH"
proj_path = "$PROJ_PATH"

# --- STL Analysis ---
if os.path.exists(stl_path):
    result["stl_exists"] = True
    result["stl_size"] = os.path.getsize(stl_path)
    
    # Check modification time
    mtime = os.path.getmtime(stl_path)
    if mtime > result["task_start"]:
        # Count triangles
        try:
            with open(stl_path, 'rb') as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    count = struct.unpack('<I', count_bytes)[0]
                    # Verify file size matches binary STL formula: 80 + 4 + (50 * count)
                    expected_size = 84 + (50 * count)
                    if abs(expected_size - result["stl_size"]) < 1024: # Allow small buffer padding
                        result["stl_triangles"] = count
                        result["stl_is_binary"] = True
                    else:
                        # Fallback for ASCII or non-standard
                        pass 
        except Exception as e:
            print(f"STL Error: {e}")

# --- Project Analysis ---
if os.path.exists(proj_path):
    result["proj_exists"] = True
    mtime = os.path.getmtime(proj_path)
    if mtime > result["task_start"]:
        try:
            if tarfile.is_tarfile(proj_path):
                result["proj_valid"] = True
                with tarfile.open(proj_path, 'r') as tar:
                    members = tar.getnames()
                    # Count mask plist files
                    masks = [m for m in members if 'mask_' in m and m.endswith('.plist')]
                    result["proj_mask_count"] = len(masks)
        except Exception as e:
            print(f"Project Error: {e}")

# Save JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="