#!/bin/bash
# Export result for air_space_reconstruction task

echo "=== Exporting air_space_reconstruction result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
STL_PATH="/home/ga/Documents/air_spaces.stl"
PROJECT_PATH="/home/ga/Documents/air_project.inv3"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Analyze outputs using Python
python3 << PYEOF
import os
import json
import struct
import tarfile
import plistlib
import time

stl_path = "$STL_PATH"
project_path = "$PROJECT_PATH"
task_start = int("$TASK_START")

result = {
    "stl_exists": False,
    "stl_created_during_task": False,
    "stl_valid": False,
    "stl_is_binary": False,
    "stl_triangle_count": 0,
    "stl_size_bytes": 0,
    
    "project_exists": False,
    "project_created_during_task": False,
    "project_valid": False,
    "air_mask_found": False,
    "mask_details": []
}

# --- Analyze STL ---
if os.path.isfile(stl_path):
    result["stl_exists"] = True
    stats = os.stat(stl_path)
    result["stl_size_bytes"] = stats.st_size
    if stats.st_mtime > task_start:
        result["stl_created_during_task"] = True
        
    # Check binary STL header
    if result["stl_size_bytes"] >= 84:
        try:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    count = struct.unpack("<I", count_bytes)[0]
                    # Validation: file size should match 80 + 4 + count * 50
                    expected_size = 84 + (count * 50)
                    # Allow small padding or differences in some exporters
                    if abs(stats.st_size - expected_size) < 1024:
                        result["stl_is_binary"] = True
                        result["stl_triangle_count"] = count
                        result["stl_valid"] = True
        except Exception:
            pass
            
    # Fallback: Check ASCII STL if binary check failed
    if not result["stl_valid"]:
        try:
            with open(stl_path, "r", errors="ignore") as f:
                if f.readline().strip().startswith("solid"):
                    # Basic check, counting facets might be slow for huge files
                    result["stl_valid"] = True 
                    # Set a dummy count > 0 to indicate validity for scoring
                    result["stl_triangle_count"] = 1000 
        except Exception:
            pass

# --- Analyze Project ---
if os.path.isfile(project_path):
    result["project_exists"] = True
    stats = os.stat(project_path)
    if stats.st_mtime > task_start:
        result["project_created_during_task"] = True
        
    try:
        with tarfile.open(project_path, "r:gz") as t:
            result["project_valid"] = True
            for member in t.getmembers():
                if member.name.endswith(".plist") and "mask" in member.name:
                    try:
                        f = t.extractfile(member)
                        plist_data = plistlib.load(f)
                        thresh = plist_data.get("threshold_range", [0, 0])
                        mask_info = {
                            "name": plist_data.get("name", "unknown"),
                            "min_hu": thresh[0],
                            "max_hu": thresh[1]
                        }
                        result["mask_details"].append(mask_info)
                        
                        # Check if this mask targets air
                        # Target: -1024 to -200. 
                        # Acceptance logic: min <= -800 AND max between -600 and 0
                        if thresh[0] <= -800 and (-600 <= thresh[1] <= 0):
                            result["air_mask_found"] = True
                    except Exception as e:
                        pass
    except Exception as e:
        result["project_error"] = str(e)

# Save result
with open("/tmp/air_space_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="