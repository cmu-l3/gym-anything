#!/bin/bash
echo "=== Exporting boolean_subtract_soft_tissue result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png

# Paths
STL_PATH="/home/ga/Documents/soft_tissue_only.stl"
PROJECT_PATH="/home/ga/Documents/boolean_masks.inv3"

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Run analysis in Python to parse binary files safely
python3 << PYEOF
import os
import json
import struct
import tarfile
import plistlib
import time

result = {
    "stl_exists": False,
    "stl_size": 0,
    "stl_valid": False,
    "stl_triangles": 0,
    "stl_created_during_task": False,
    "project_exists": False,
    "project_valid": False,
    "project_mask_count": 0,
    "masks": [],
    "project_created_during_task": False
}

task_start = $TASK_START
stl_path = "$STL_PATH"
project_path = "$PROJECT_PATH"

# --- STL ANALYSIS ---
if os.path.isfile(stl_path):
    result["stl_exists"] = True
    stats = os.stat(stl_path)
    result["stl_size"] = stats.st_size
    if stats.st_mtime > task_start:
        result["stl_created_during_task"] = True

    # Check for Binary STL
    try:
        if stats.st_size >= 84:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    tri_count = struct.unpack("<I", count_bytes)[0]
                    # Verify file size matches triangle count formula: 80 + 4 + (50 * N)
                    expected_size = 84 + (50 * tri_count)
                    if abs(stats.st_size - expected_size) < 1024:  # Allow small padding
                        result["stl_valid"] = True
                        result["stl_triangles"] = tri_count
    except Exception as e:
        print(f"STL Check Error: {e}")

    # Fallback: Check for ASCII STL
    if not result["stl_valid"]:
        try:
            with open(stl_path, "r", errors="ignore") as f:
                head = f.read(100).lower()
                if "solid" in head:
                    result["stl_valid"] = True
                    # Rough estimate or leave 0
        except:
            pass

# --- PROJECT ANALYSIS ---
if os.path.isfile(project_path):
    result["project_exists"] = True
    stats = os.stat(project_path)
    if stats.st_mtime > task_start:
        result["project_created_during_task"] = True
    
    try:
        if tarfile.is_tarfile(project_path):
            with tarfile.open(project_path, "r:*") as tar:
                # Iterate members to find mask lists
                for member in tar.getmembers():
                    if member.name == "main.plist":
                        # Main project file
                        try:
                            f = tar.extractfile(member)
                            plist = plistlib.load(f)
                            # count masks referenced in main plist if possible, 
                            # but sometimes it's better to count mask_*.plist files
                        except:
                            pass
                    
                    if member.name.startswith("mask_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            mask_data = plistlib.load(f)
                            mask_info = {
                                "name": mask_data.get("name", "unknown"),
                                "threshold_range": mask_data.get("threshold_range", [0,0]),
                                "color": mask_data.get("color", [0,0,0])
                            }
                            result["masks"].append(mask_info)
                        except:
                            pass
                
                result["project_mask_count"] = len(result["masks"])
                result["project_valid"] = True
    except Exception as e:
        print(f"Project Check Error: {e}")

# Save Result
with open("/tmp/boolean_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Analysis complete. JSON generated."
cat /tmp/boolean_result.json