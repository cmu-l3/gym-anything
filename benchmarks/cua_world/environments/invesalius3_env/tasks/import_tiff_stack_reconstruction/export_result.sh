#!/bin/bash
echo "=== Exporting import_tiff_stack_reconstruction results ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_FILE="/home/ga/Documents/calibrated_model.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze Output File (Python Script)
# We embed a python script to parse the STL and calculate bounding box
python3 << 'EOF'
import struct
import os
import json
import time

output_path = "/home/ga/Documents/calibrated_model.stl"
task_start_time = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start_time = int(f.read().strip())
except:
    pass

result = {
    "exists": False,
    "valid_stl": False,
    "created_during_task": False,
    "triangle_count": 0,
    "file_size": 0,
    "dimensions": {
        "x_width": 0.0,
        "y_height": 0.0,
        "z_depth": 0.0,
        "min_x": 0.0, "max_x": 0.0,
        "min_y": 0.0, "max_y": 0.0,
        "min_z": 0.0, "max_z": 0.0
    }
}

if os.path.exists(output_path):
    result["exists"] = True
    stat = os.stat(output_path)
    result["file_size"] = stat.st_size
    if stat.st_mtime > task_start_time:
        result["created_during_task"] = True

    # Parse Binary STL to get geometry
    # Header: 80 bytes
    # Count: 4 bytes (uint32)
    # Triangles: 50 bytes each (Normal + 3 Vertices + Attr)
    try:
        with open(output_path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) == 4:
                num_triangles = struct.unpack("<I", count_bytes)[0]
                expected_size = 84 + (num_triangles * 50)
                
                # Loose check for validity (filesize match)
                if abs(expected_size - result["file_size"]) < 1024:
                    result["valid_stl"] = True
                    result["triangle_count"] = num_triangles
                    
                    # Read vertices to calculate bounding box
                    # We can iterate efficiently
                    min_x, max_x = float('inf'), float('-inf')
                    min_y, max_y = float('inf'), float('-inf')
                    min_z, max_z = float('inf'), float('-inf')
                    
                    # Read in chunks to avoid memory issues with huge files
                    # But for simple verification, checking a subset or streaming is better
                    # Let's stream read
                    for _ in range(num_triangles):
                        data = f.read(50)
                        if len(data) < 50: break
                        # Unpack 12 floats (Normal: 3, V1: 3, V2: 3, V3: 3)
                        # We only need V1, V2, V3 (indices 3-11 in the float array)
                        floats = struct.unpack("<12f", data[:48])
                        
                        for i in range(3, 12, 3): # v1, v2, v3
                            vx, vy, vz = floats[i], floats[i+1], floats[i+2]
                            if vx < min_x: min_x = vx
                            if vx > max_x: max_x = vx
                            if vy < min_y: min_y = vy
                            if vy > max_y: max_y = vy
                            if vz < min_z: min_z = vz
                            if vz > max_z: max_z = vz
                            
                    if min_x != float('inf'):
                        result["dimensions"]["x_width"] = max_x - min_x
                        result["dimensions"]["y_height"] = max_y - min_y
                        result["dimensions"]["z_depth"] = max_z - min_z
                        result["dimensions"]["min_x"] = min_x
                        result["dimensions"]["max_x"] = max_x
    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="