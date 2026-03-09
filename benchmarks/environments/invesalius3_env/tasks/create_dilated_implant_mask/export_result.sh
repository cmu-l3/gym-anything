#!/bin/bash
echo "=== Exporting create_dilated_implant_mask result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
ANATOMICAL_FILE="/home/ga/Documents/anatomical_skull.stl"
DILATED_FILE="/home/ga/Documents/dilated_skull.stl"
RESULT_JSON="/tmp/dilated_mask_result.json"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Run Python script to analyze STL files (volume, validity, timestamp)
python3 << PYEOF
import os
import struct
import json
import numpy as np
import time

anatomical_path = "$ANATOMICAL_FILE"
dilated_path = "$DILATED_FILE"
task_start = int("$TASK_START")

result = {
    "anatomical": {
        "exists": False,
        "valid": False,
        "volume": 0.0,
        "triangles": 0,
        "created_during_task": False
    },
    "dilated": {
        "exists": False,
        "valid": False,
        "volume": 0.0,
        "triangles": 0,
        "created_during_task": False
    },
    "comparison": {
        "volume_ratio": 0.0,
        "is_larger": False
    }
}

def calculate_signed_volume(stl_path):
    """
    Calculate volume of a binary STL using signed tetrahedrons.
    Returns volume in cm^3 (assuming STL units are mm).
    """
    try:
        if os.path.getsize(stl_path) < 84:
            return 0, 0
        
        with open(stl_path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            num_triangles = struct.unpack("<I", count_bytes)[0]
            
            # Sanity check file size
            expected_size = 84 + num_triangles * 50
            if abs(os.path.getsize(stl_path) - expected_size) > 1024:
                # Might be ASCII or corrupt, simple binary check failed
                return 0, 0

            # Read all triangles at once if possible, or chunk it
            # STL format: normal (3f), v1 (3f), v2 (3f), v3 (3f), attr (2B) = 50 bytes
            dtype = np.dtype([
                ('normal', '<f4', (3,)),
                ('v1', '<f4', (3,)),
                ('v2', '<f4', (3,)),
                ('v3', '<f4', (3,)),
                ('attr', '<u2')
            ])
            
            data = np.fromfile(f, dtype=dtype, count=num_triangles)
            
            v1 = data['v1']
            v2 = data['v2']
            v3 = data['v3']
            
            # Volume = sum(dot(cross(v1, v2), v3)) / 6.0
            cross_prod = np.cross(v1, v2)
            # Dot product along the last axis
            dot_prod = np.einsum('ij,ij->i', cross_prod, v3)
            total_vol = np.sum(dot_prod) / 6.0
            
            # Convert mm^3 to cm^3
            return abs(total_vol) / 1000.0, num_triangles
    except Exception as e:
        print(f"Error calculating volume for {stl_path}: {e}")
        return 0, 0

def analyze_file(path, key):
    if os.path.exists(path):
        result[key]["exists"] = True
        mtime = os.path.getmtime(path)
        if mtime > task_start:
            result[key]["created_during_task"] = True
            
        vol, tris = calculate_signed_volume(path)
        if tris > 0:
            result[key]["valid"] = True
            result[key]["volume"] = vol
            result[key]["triangles"] = tris

# Analyze both files
analyze_file(anatomical_path, "anatomical")
analyze_file(dilated_path, "dilated")

# Compare
v_anat = result["anatomical"]["volume"]
v_dil = result["dilated"]["volume"]

if v_anat > 0:
    ratio = v_dil / v_anat
    result["comparison"]["volume_ratio"] = ratio
    # Threshold check: dilated should be strictly larger
    if ratio > 1.0:
        result["comparison"]["is_larger"] = True

# Write result
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

cat "$RESULT_JSON"
echo "=== Export Complete ==="