#!/bin/bash
echo "=== Exporting export_hemicranium_model result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/left_hemicranium.stl"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the STL file using Python to get geometry stats
# We calculate bounding box to verify it's a hemi-cranium (half width)
python3 << 'PYEOF'
import struct
import os
import json
import math

output_file = "/home/ga/Documents/left_hemicranium.stl"
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_valid_stl": False,
    "triangle_count": 0,
    "bbox_width": 0.0,
    "bbox_length": 0.0,
    "bbox_height": 0.0,
    "aspect_ratio_width_length": 0.0,
    "created_during_task": False
}

if os.path.isfile(output_file):
    result["file_exists"] = True
    stat = os.stat(output_file)
    result["file_size_bytes"] = stat.st_size
    
    # Check timestamp
    task_start = float(os.environ.get("TASK_START", 0))
    if stat.st_mtime > task_start:
        result["created_during_task"] = True

    # Parse Binary STL to get vertices for Bounding Box
    try:
        with open(output_file, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            
            if len(count_bytes) == 4:
                count = struct.unpack("<I", count_bytes)[0]
                result["triangle_count"] = count
                
                # Check if file size matches binary STL expectation
                expected_size = 84 + (count * 50)
                # Allow small buffer or exact match
                if abs(expected_size - result["file_size_bytes"]) < 1024:
                    result["is_valid_stl"] = True
                    
                    # Read vertices to calc bounding box
                    # We won't read ALL if it's huge, but we need enough to get extents.
                    # For accuracy, we should read all. A skull is ~200k-500k tris = ~25MB. 
                    # This is fast enough in Python.
                    
                    min_x, max_x = float('inf'), float('-inf')
                    min_y, max_y = float('inf'), float('-inf')
                    min_z, max_z = float('inf'), float('-inf')
                    
                    # We process in chunks to avoid memory spikes if file is huge
                    chunk_size = 1000
                    
                    for i in range(count):
                        # 12 floats (normal + 3 vertices), 2 bytes attribute
                        # 4*3 = 12 bytes normal
                        # 4*3 = 12 bytes v1
                        # 4*3 = 12 bytes v2
                        # 4*3 = 12 bytes v3
                        # 2 bytes attr
                        # Total 50 bytes
                        data = f.read(50)
                        if len(data) < 50: 
                            break
                            
                        # Unpack 3 vertices (skip normal at offset 0-11)
                        # v1 at 12, v2 at 24, v3 at 36
                        floats = struct.unpack("<3f3f3f", data[12:48])
                        
                        # v1
                        x, y, z = floats[0], floats[1], floats[2]
                        if x < min_x: min_x = x
                        if x > max_x: max_x = x
                        if y < min_y: min_y = y
                        if y > max_y: max_y = y
                        if z < min_z: min_z = z
                        if z > max_z: max_z = z
                        
                        # v2
                        x, y, z = floats[3], floats[4], floats[5]
                        if x < min_x: min_x = x
                        if x > max_x: max_x = x
                        if y < min_y: min_y = y
                        if y > max_y: max_y = y
                        if z < min_z: min_z = z
                        if z > max_z: max_z = z

                        # v3
                        x, y, z = floats[6], floats[7], floats[8]
                        if x < min_x: min_x = x
                        if x > max_x: max_x = x
                        if y < min_y: min_y = y
                        if y > max_y: max_y = y
                        if z < min_z: min_z = z
                        if z > max_z: max_z = z

                    if min_x != float('inf'):
                        width = max_x - min_x
                        length = max_y - min_y
                        height = max_z - min_z
                        
                        result["bbox_width"] = width
                        result["bbox_length"] = length
                        result["bbox_height"] = height
                        
                        # Sort dimensions to handle coordinate system rotation variances 
                        # usually Z is height in DICOM, but sometimes STL export swaps Y/Z.
                        # For a skull: Length (AP) > Width (RL) > Height (SI) usually for full skull.
                        # For Hemicranium: Length (AP) > Height (SI) > Width (RL).
                        # We specifically want to find the ratio of the Shortest principal axis to the Longest principal axis.
                        
                        dims = sorted([width, length, height])
                        # Smallest dim is likely the cropped width
                        # Largest dim is likely the length
                        if dims[2] > 0:
                            result["aspect_ratio_width_length"] = dims[0] / dims[2]

    except Exception as e:
        result["error"] = str(e)

# Fallback for ASCII STL if binary check failed but file exists
if result["file_exists"] and not result["is_valid_stl"]:
    try:
        with open(output_file, "r", errors="ignore") as f:
            if f.readline().strip().startswith("solid"):
                result["is_valid_stl"] = True
                # We won't parse ASCII for bbox in this script (too slow/complex), 
                # but we give credit for valid format.
                result["is_ascii"] = True
    except:
        pass

with open("/tmp/export_hemicranium_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="