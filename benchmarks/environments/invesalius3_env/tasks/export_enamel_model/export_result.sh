#!/bin/bash
# Export result for export_enamel_model task

echo "=== Exporting export_enamel_model result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run Python analysis script
# This script calculates the STL volume and checks the InVesalius project file
python3 << 'PYEOF'
import os
import json
import struct
import tarfile
import plistlib
import math

stl_path = "/home/ga/Documents/enamel_model.stl"
project_path = "/home/ga/Documents/enamel_project.inv3"

result = {
    "stl_exists": False,
    "stl_valid": False,
    "stl_volume_mm3": 0.0,
    "stl_triangle_count": 0,
    "project_exists": False,
    "project_valid": False,
    "mask_min_hu": None,
    "mask_max_hu": None,
    "high_density_mask_found": False
}

def calculate_signed_volume(p1, p2, p3):
    """Calculate signed volume of tetrahedron formed by triangle and origin."""
    v321 = p3[0]*p2[1]*p1[2]
    v231 = p2[0]*p3[1]*p1[2]
    v312 = p3[0]*p1[1]*p2[2]
    v132 = p1[0]*p3[1]*p2[2]
    v213 = p2[0]*p1[1]*p3[2]
    v123 = p1[0]*p2[1]*p3[2]
    return (1.0/6.0) * (-v321 + v231 + v312 - v132 - v213 + v123)

# --- Analyze STL ---
if os.path.isfile(stl_path):
    result["stl_exists"] = True
    try:
        file_size = os.path.getsize(stl_path)
        if file_size >= 84:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                count = struct.unpack("<I", count_bytes)[0]
                
                # Validation: check if file size matches expected size for binary STL
                expected_size = 80 + 4 + count * 50
                # Allow a small buffer for footer or padding, though strict binary STL shouldn't have it
                if abs(file_size - expected_size) < 1024:
                    result["stl_valid"] = True
                    result["stl_triangle_count"] = count
                    
                    # Calculate volume
                    total_vol = 0.0
                    # Read all triangles at once if possible, or chunk it
                    # 50 bytes per triangle: 12 floats (normal + 3 vertices) + 2 byte attr
                    for _ in range(count):
                        data = f.read(50)
                        if len(data) < 50:
                            break
                        # floats are little-endian
                        floats = struct.unpack("<12f", data[:48])
                        # Normal is floats[0:3], v1 is [3:6], v2 is [6:9], v3 is [9:12]
                        p1 = floats[3:6]
                        p2 = floats[6:9]
                        p3 = floats[9:12]
                        total_vol += calculate_signed_volume(p1, p2, p3)
                    
                    result["stl_volume_mm3"] = abs(total_vol)
    except Exception as e:
        result["stl_error"] = str(e)

# --- Analyze Project ---
if os.path.isfile(project_path):
    result["project_exists"] = True
    try:
        with tarfile.open(project_path, "r:gz") as t:
            result["project_valid"] = True
            max_lower_thresh = -9999
            
            # Look for mask plist files
            for member in t.getmembers():
                if member.name.startswith("mask_") and member.name.endswith(".plist"):
                    f = t.extractfile(member)
                    mask_data = plistlib.load(f)
                    thresh = mask_data.get("threshold_range", [0, 0])
                    
                    # Keep track of the mask with the highest lower-bound (most restrictive)
                    if thresh[0] > max_lower_thresh:
                        max_lower_thresh = thresh[0]
                        result["mask_min_hu"] = thresh[0]
                        result["mask_max_hu"] = thresh[1]
            
            if result["mask_min_hu"] is not None and result["mask_min_hu"] >= 1400:
                result["high_density_mask_found"] = True

    except Exception as e:
        result["project_error"] = str(e)

# Save result
with open("/tmp/export_enamel_model_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="