#!/bin/bash
set -e
echo "=== Exporting dense_structure_volume_report result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# Run analysis in Python (embedded to handle STL parsing and plist reading)
python3 << 'PYEOF'
import os
import json
import struct
import tarfile
import plistlib
import re

# Paths
stl_path = "/home/ga/Documents/dense_structures.stl"
report_path = "/home/ga/Documents/dense_volume_report.txt"
project_path = "/home/ga/Documents/dense_analysis.inv3"
start_time_path = "/tmp/task_start_time.txt"

# Helper: Load start time
try:
    with open(start_time_path, 'r') as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

result = {
    "stl_exists": False,
    "stl_valid": False,
    "stl_triangles": 0,
    "stl_volume_ml": 0.0,
    "stl_created_after_start": False,
    
    "project_exists": False,
    "project_valid": False,
    "mask_threshold_min": -1,
    "mask_threshold_max": -1,
    "project_created_after_start": False,
    
    "report_exists": False,
    "reported_volume_ml": 0.0,
    "report_created_after_start": False
}

# --- 1. Analyze STL ---
if os.path.exists(stl_path):
    result["stl_exists"] = True
    mtime = os.path.getmtime(stl_path)
    if mtime > task_start_time:
        result["stl_created_after_start"] = True
    
    try:
        if os.path.getsize(stl_path) > 84:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                tri_count = struct.unpack("<I", count_bytes)[0]
                
                # Verify file size matches triangle count
                expected_size = 80 + 4 + (tri_count * 50)
                if abs(os.path.getsize(stl_path) - expected_size) < 1024:
                    result["stl_valid"] = True
                    result["stl_triangles"] = tri_count
                    
                    # Calculate approximate volume from mesh (signed tetrahedron volume)
                    # p1(x,y,z), p2, p3. normal(nx,ny,nz)
                    # vol = sum(dot(p1, cross(p2, p3))) / 6
                    total_vol = 0.0
                    for _ in range(tri_count):
                        data = f.read(50)
                        # normal(3f), v1(3f), v2(3f), v3(3f), attr(2s)
                        # We need v1, v2, v3. offsets: 12, 24, 36
                        v1 = struct.unpack("<3f", data[12:24])
                        v2 = struct.unpack("<3f", data[24:36])
                        v3 = struct.unpack("<3f", data[36:48])
                        
                        # Cross product v2 x v3
                        cp_x = v2[1]*v3[2] - v2[2]*v3[1]
                        cp_y = v2[2]*v3[0] - v2[0]*v3[2]
                        cp_z = v2[0]*v3[1] - v2[1]*v3[0]
                        
                        # Dot product v1 . cp
                        det = v1[0]*cp_x + v1[1]*cp_y + v1[2]*cp_z
                        total_vol += det
                    
                    result["stl_volume_ml"] = abs(total_vol) / 6000.0 # mm3 to mL (approx / 1000)
                    # wait, mm3 to cm3 is /1000. mL is cm3.
                    result["stl_volume_ml"] = abs(total_vol) / 6000.0
    except Exception as e:
        result["stl_error"] = str(e)

# --- 2. Analyze Project (Mask Thresholds) ---
if os.path.exists(project_path):
    result["project_exists"] = True
    if os.path.getmtime(project_path) > task_start_time:
        result["project_created_after_start"] = True
        
    try:
        with tarfile.open(project_path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.name.startswith("mask_") and member.name.endswith(".plist"):
                    f = tar.extractfile(member)
                    plist = plistlib.load(f)
                    thresh = plist.get("threshold_range", [0, 0])
                    # If multiple masks, take the one that looks most like our target (high range)
                    if thresh[0] > result["mask_threshold_min"]: 
                        result["mask_threshold_min"] = thresh[0]
                        result["mask_threshold_max"] = thresh[1]
            result["project_valid"] = True
    except Exception as e:
        result["project_error"] = str(e)

# --- 3. Analyze Report ---
if os.path.exists(report_path):
    result["report_exists"] = True
    if os.path.getmtime(report_path) > task_start_time:
        result["report_created_after_start"] = True
    
    try:
        with open(report_path, "r") as f:
            content = f.read()
            # Find a float number
            matches = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            if matches:
                # Take the last number found as likely volume
                result["reported_volume_ml"] = float(matches[-1])
    except Exception as e:
        result["report_error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="