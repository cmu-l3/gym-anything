#!/bin/bash
set -e
echo "=== Exporting crop_calvarium_export result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_FILE="/home/ga/Documents/calvarium_only.stl"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Analyze STL File using Python (embedded)
# We calculate triangle count and bounding box ratio to verify cropping.
python3 << PYEOF
import struct
import os
import json
import math

output_file = "$OUTPUT_FILE"
task_start = int("$TASK_START")
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_during_task": False,
    "is_binary_stl": False,
    "triangle_count": 0,
    "bounding_box_ratio": 1.0,
    "min_dim": 0.0,
    "max_dim": 0.0,
    "dims": [0, 0, 0],
    "error": None
}

if os.path.exists(output_file):
    result["file_exists"] = True
    stats = os.stat(output_file)
    result["file_size_bytes"] = stats.st_size
    
    # Check modification time
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        # Basic Binary STL Parsing
        # Header: 80 bytes
        # Triangle Count: 4 bytes (unsigned int)
        # Triangles: 50 bytes each (normal + 3 vertices + attr)
        
        if result["file_size_bytes"] >= 84:
            with open(output_file, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    tri_count = struct.unpack("<I", count_bytes)[0]
                    expected_size = 84 + (tri_count * 50)
                    
                    # Verify size matches binary STL spec (allow tiny tolerance for padding)
                    if abs(stats.st_size - expected_size) < 1024:
                        result["is_binary_stl"] = True
                        result["triangle_count"] = tri_count
                        
                        # Calculate Bounding Box
                        # We need to read vertices to determine spatial extent.
                        # Reading all is slow in Python loop, so we sample if too large, 
                        # or read in chunks. For scoring, even reading first 10k triangles 
                        # gives a good approximation of extent if mesh isn't weirdly sorted.
                        # However, let's try to read min/max of the whole file efficiently.
                        
                        min_x, min_y, min_z = float('inf'), float('inf'), float('inf')
                        max_x, max_y, max_z = float('-inf'), float('-inf'), float('-inf')
                        
                        # Read in chunks of triangles
                        chunk_size = 1000
                        bytes_per_tri = 50
                        chunk_bytes = chunk_size * bytes_per_tri
                        
                        # Seek to first triangle
                        f.seek(84)
                        
                        vertices_read = 0
                        while vertices_read < tri_count:
                            # Safety break for huge files to prevent timeout
                            if vertices_read > 500000: 
                                break
                                
                            data = f.read(chunk_bytes)
                            if not data: break
                            
                            num_tris_in_chunk = len(data) // 50
                            
                            for i in range(num_tris_in_chunk):
                                offset = i * 50 + 12 # Skip normal (12 bytes)
                                # Read 3 vertices (3 floats each) = 36 bytes
                                # struct unpack 9 floats
                                try:
                                    verts = struct.unpack("<fffffffff", data[offset:offset+36])
                                    # xs: 0, 3, 6; ys: 1, 4, 7; zs: 2, 5, 8
                                    for j in range(3):
                                        x, y, z = verts[j*3], verts[j*3+1], verts[j*3+2]
                                        if x < min_x: min_x = x
                                        if x > max_x: max_x = x
                                        if y < min_y: min_y = y
                                        if y > max_y: max_y = y
                                        if z < min_z: min_z = z
                                        if z > max_z: max_z = z
                                except:
                                    pass
                            
                            vertices_read += num_tris_in_chunk
                        
                        if min_x != float('inf'):
                            dx = max_x - min_x
                            dy = max_y - min_y
                            dz = max_z - min_z
                            dims = [dx, dy, dz]
                            result["dims"] = dims
                            if max(dims) > 0:
                                result["min_dim"] = min(dims)
                                result["max_dim"] = max(dims)
                                result["bounding_box_ratio"] = min(dims) / max(dims)
                            
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "=== Export complete ==="