#!/bin/bash
echo "=== Exporting custom_threshold_alveolar_export result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/alveolar_study.inv3"
STL_PATH="/home/ga/Documents/alveolar_surface.stl"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze files using Python
python3 << PYEOF
import os
import json
import tarfile
import plistlib
import struct

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": False,
    "project_valid": False,
    "stl_exists": False,
    "stl_valid": False,
    "stl_triangles": 0,
    "stl_size_kb": 0,
    "mask_thresholds": [],
    "files_created_during_task": False
}

project_path = "$PROJECT_PATH"
stl_path = "$STL_PATH"

# 1. Analyze Project File (.inv3 is a tar.gz containing plists)
if os.path.exists(project_path):
    result["project_exists"] = True
    mtime = os.path.getmtime(project_path)
    if mtime > result["task_start"]:
        result["files_created_during_task"] = True
    
    try:
        if tarfile.is_tarfile(project_path):
            with tarfile.open(project_path, "r:*") as tar:
                result["project_valid"] = True
                for member in tar.getmembers():
                    # Look for mask files (e.g., mask_0.plist)
                    if member.name.startswith("mask") and member.name.endswith(".plist"):
                        f = tar.extractfile(member)
                        if f:
                            try:
                                pl = plistlib.load(f)
                                # Extract threshold range
                                thresh = pl.get("threshold_range", [0, 0])
                                result["mask_thresholds"].append({
                                    "name": pl.get("name", "Unknown"),
                                    "min": float(thresh[0]),
                                    "max": float(thresh[1])
                                })
                            except Exception as e:
                                print(f"Error parsing plist {member.name}: {e}")
    except Exception as e:
        print(f"Error reading project file: {e}")

# 2. Analyze STL File
if os.path.exists(stl_path):
    result["stl_exists"] = True
    size = os.path.getsize(stl_path)
    result["stl_size_kb"] = size / 1024.0
    mtime = os.path.getmtime(stl_path)
    if mtime > result["task_start"]:
        # If project wasn't new, maybe STL is
        if not result["files_created_during_task"]:
             result["files_created_during_task"] = True

    # Check for binary STL header and triangle count
    if size > 84:
        try:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                tri_count = struct.unpack("<I", count_bytes)[0]
                # Simple validation: file size roughly matches triangle count
                expected_size = 84 + (tri_count * 50)
                if abs(expected_size - size) < 1024:
                    result["stl_valid"] = True
                    result["stl_triangles"] = tri_count
                else:
                    # Fallback check for ASCII STL
                    f.seek(0)
                    start = f.read(5)
                    if start == b"solid":
                        result["stl_valid"] = True
                        # Counting ASCII triangles is expensive, assume valid if header is solid
                        result["stl_triangles"] = 10000 # Placeholder for non-zero
        except Exception as e:
            print(f"Error reading STL: {e}")

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="