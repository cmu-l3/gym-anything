#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
PROJECT_PATH="/home/ga/Documents/cortical_project.inv3"
STL_PATH="/home/ga/Documents/cortical_bone.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to analyze both output files
python3 << PYEOF
import os
import json
import tarfile
import plistlib
import struct

result = {
    "project_exists": False,
    "project_valid": False,
    "masks": [],
    "surfaces_in_project": 0,
    "stl_exists": False,
    "stl_valid": False,
    "stl_triangle_count": 0,
    "stl_is_binary": False,
    "stl_size_bytes": 0,
    "files_created_during_task": False
}

project_path = "$PROJECT_PATH"
stl_path = "$STL_PATH"
task_start = $TASK_START

# --- Analyze Project File (.inv3) ---
if os.path.exists(project_path):
    result["project_exists"] = True
    mtime = os.path.getmtime(project_path)
    if mtime > task_start:
        result["files_created_during_task"] = True
    
    try:
        if tarfile.is_tarfile(project_path):
            with tarfile.open(project_path, "r:*") as tar:
                result["project_valid"] = True
                
                # Scan members
                for member in tar.getmembers():
                    # Parse Mask Plists
                    if member.name.startswith("mask_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            if f:
                                plist_data = plistlib.load(f)
                                thresh = plist_data.get("threshold_range", [0, 0])
                                result["masks"].append({
                                    "name": plist_data.get("name", "Unknown"),
                                    "threshold_min": thresh[0],
                                    "threshold_max": thresh[1]
                                })
                        except Exception as e:
                            print(f"Error parsing mask {member.name}: {e}")
                    
                    # Count Surfaces
                    if member.name.startswith("surface_") and member.name.endswith(".plist"):
                        result["surfaces_in_project"] += 1
    except Exception as e:
        print(f"Error analyzing project file: {e}")

# --- Analyze STL File ---
if os.path.exists(stl_path):
    result["stl_exists"] = True
    result["stl_size_bytes"] = os.path.getsize(stl_path)
    mtime = os.path.getmtime(stl_path)
    # If project was created during task, likely STL was too, but check logic specifically if needed
    if mtime > task_start:
        result["files_created_during_task"] = result["files_created_during_task"] or True

    # Check Binary STL
    if result["stl_size_bytes"] >= 84:
        try:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    num_triangles = struct.unpack("<I", count_bytes)[0]
                    expected_size = 84 + (num_triangles * 50)
                    # Allow 84-byte tolerance for sloppy headers
                    if abs(result["stl_size_bytes"] - expected_size) < 100:
                        result["stl_valid"] = True
                        result["stl_is_binary"] = True
                        result["stl_triangle_count"] = num_triangles
        except Exception as e:
            print(f"Error reading binary STL: {e}")

    # Check ASCII STL (fallback)
    if not result["stl_valid"]:
        try:
            with open(stl_path, "r", encoding="utf-8", errors="ignore") as f:
                start = f.read(1024)
                if "solid" in start and "facet normal" in start:
                    result["stl_valid"] = True
                    result["stl_is_binary"] = False
                    # Estimate count (rough) or recount
                    f.seek(0)
                    result["stl_triangle_count"] = sum(1 for line in f if "endfacet" in line)
        except Exception:
            pass

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="