#!/bin/bash
set -e

echo "=== Exporting bitmap_stack_reconstruction results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_STL="/home/ga/Documents/calibrated_skull.stl"
RESULT_JSON="/tmp/bitmap_stack_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Calculate STL metrics using Python
cat << 'PYEOF' > /tmp/analyze_stl.py
import sys
import os
import struct
import json
import math

stl_path = sys.argv[1]
json_path = sys.argv[2]

result = {
    "exists": False,
    "file_size": 0,
    "valid_header": False,
    "triangle_count": 0,
    "z_min": 0.0,
    "z_max": 0.0,
    "z_height": 0.0,
    "x_width": 0.0,
    "y_depth": 0.0,
    "is_binary": False
}

if os.path.exists(stl_path):
    result["exists"] = True
    result["file_size"] = os.path.getsize(stl_path)
    
    try:
        with open(stl_path, 'rb') as f:
            header = f.read(80)
            count_bytes = f.read(4)
            
            if len(count_bytes) == 4:
                num_triangles = struct.unpack('<I', count_bytes)[0]
                expected_size = 84 + num_triangles * 50
                
                # Check if file size matches binary STL expectation
                if abs(expected_size - result["file_size"]) < 1000:
                    result["is_binary"] = True
                    result["valid_header"] = True
                    result["triangle_count"] = num_triangles
                    
                    # Read vertices to find bounding box
                    # We can't read all if it's huge, but let's read a strided sample or all if reasonable
                    # For accuracy, we need strict Z bounds.
                    # Reading 500k triangles is ~25MB, fast enough.
                    
                    min_x, max_x = float('inf'), float('-inf')
                    min_y, max_y = float('inf'), float('-inf')
                    min_z, max_z = float('inf'), float('-inf')
                    
                    # Read in chunks
                    chunk_size = 1000
                    f.seek(84)
                    
                    for _ in range(0, num_triangles, chunk_size):
                        chunk = f.read(50 * chunk_size)
                        if not chunk:
                            break
                        
                        # Process chunk
                        num_in_chunk = len(chunk) // 50
                        for i in range(num_in_chunk):
                            offset = i * 50 + 12 # Skip normal (12 bytes)
                            # 3 vertices, each 3 floats (4 bytes)
                            # V1
                            data = struct.unpack('<3f', chunk[offset:offset+12])
                            min_z = min(min_z, data[2])
                            max_z = max(max_z, data[2])
                            min_x = min(min_x, data[0])
                            max_x = max(max_x, data[0])
                            min_y = min(min_y, data[1])
                            max_y = max(max_y, data[1])
                            
                            # V2
                            data = struct.unpack('<3f', chunk[offset+12:offset+24])
                            min_z = min(min_z, data[2])
                            max_z = max(max_z, data[2])
                            
                            # V3
                            data = struct.unpack('<3f', chunk[offset+24:offset+36])
                            min_z = min(min_z, data[2])
                            max_z = max(max_z, data[2])
                            
                    if min_z != float('inf'):
                        result["z_min"] = min_z
                        result["z_max"] = max_z
                        result["z_height"] = max_z - min_z
                        result["x_width"] = max_x - min_x
                        result["y_depth"] = max_y - min_y

    except Exception as e:
        result["error"] = str(e)

with open(json_path, 'w') as f:
    json.dump(result, f)

print(f"Analysis complete. Height: {result.get('z_height', 0)}")
PYEOF

python3 /tmp/analyze_stl.py "$OUTPUT_STL" "$RESULT_JSON"

# Check timestamp
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
if [ -f "$OUTPUT_STL" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_STL")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Add timestamp info to result
python3 -c "import json; d=json.load(open('$RESULT_JSON')); d['created_during_task']=$FILE_CREATED_DURING_TASK; json.dump(d, open('$RESULT_JSON','w'))"

# Secure copy to /tmp/task_result.json for verifier
cp "$RESULT_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export complete ==="