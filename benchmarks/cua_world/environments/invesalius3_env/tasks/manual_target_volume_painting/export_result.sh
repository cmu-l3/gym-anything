#!/bin/bash
echo "=== Exporting manual_target_volume_painting result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/target_volume.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze the STL file using Python to check geometry (Z-height is critical)
# We expect a flat-ish object (painted on 3 slices), not a full skull.
python3 << 'PYEOF'
import struct
import os
import json
import math
import sys

output_file = "/home/ga/Documents/target_volume.stl"
task_start = int(os.environ.get("TASK_START", 0))

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "file_size_bytes": 0,
    "triangle_count": 0,
    "bounds_z_min": 0.0,
    "bounds_z_max": 0.0,
    "z_height": 0.0,
    "is_flat_target": False,
    "is_empty": True
}

if os.path.isfile(output_file):
    result["file_exists"] = True
    stats = os.stat(output_file)
    result["file_size_bytes"] = stats.st_size
    
    # Check creation time
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True

    # Parse STL to get bounds
    try:
        with open(output_file, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) == 4:
                count = struct.unpack("<I", count_bytes)[0]
                result["triangle_count"] = count
                
                if count > 0:
                    result["is_empty"] = False
                    
                    # Read vertices to find bounds
                    # Binary STL: 50 bytes per triangle (12 floats + 2 bytes padding)
                    # We need to read all vertices to find Z min/max
                    
                    min_z = float('inf')
                    max_z = float('-inf')
                    
                    # Read in chunks to avoid memory issues with huge files
                    chunk_size = 1000
                    
                    for i in range(0, count, chunk_size):
                        this_chunk = min(chunk_size, count - i)
                        data = f.read(50 * this_chunk)
                        if not data: break
                        
                        for j in range(this_chunk):
                            # Offset: normal(12) + v1(12) + v2(12) + v3(12) + attr(2)
                            # We want v1, v2, v3. 
                            # v1 starts at 12, v2 at 24, v3 at 36 relative to triangle start
                            base = j * 50
                            
                            # v1 z
                            z1 = struct.unpack_from("<f", data, base + 20)[0]
                            # v2 z
                            z2 = struct.unpack_from("<f", data, base + 32)[0]
                            # v3 z
                            z3 = struct.unpack_from("<f", data, base + 44)[0]
                            
                            min_z = min(min_z, z1, z2, z3)
                            max_z = max(max_z, z1, z2, z3)
                    
                    if min_z != float('inf'):
                        result["bounds_z_min"] = min_z
                        result["bounds_z_max"] = max_z
                        result["z_height"] = max_z - min_z
                        
                        # Logic: 3 slices * 1.5mm spacing = 4.5mm. 
                        # Allow tolerance for surface smoothing/partial volume effects.
                        # If > 50mm, it's definitely not a manually painted slice target.
                        if 1.0 < result["z_height"] < 30.0:
                            result["is_flat_target"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Move result to final location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="