#!/bin/bash
echo "=== Exporting segment_frontal_sinus_cavity result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/frontal_sinus.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the STL file to calculate Volume and Centroid
# We use an embedded Python script to parse the binary STL
python3 << 'PYEOF'
import struct
import os
import json
import math

output_path = "/home/ga/Documents/frontal_sinus.stl"
result = {
    "file_exists": False,
    "file_size": 0,
    "is_valid_stl": False,
    "triangle_count": 0,
    "volume_mm3": 0.0,
    "bbox": {"min": [0,0,0], "max": [0,0,0]},
    "centroid": [0,0,0]
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)

    try:
        with open(output_path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            
            if len(count_bytes) == 4:
                count = struct.unpack("<I", count_bytes)[0]
                expected_size = 80 + 4 + count * 50
                
                # Check if size matches binary STL spec (allow some padding/slack)
                if abs(result["file_size"] - expected_size) < 1024:
                    result["is_valid_stl"] = True
                    result["triangle_count"] = count
                    
                    # Calculate volume and bounding box
                    total_vol = 0.0
                    min_x, min_y, min_z = float('inf'), float('inf'), float('inf')
                    max_x, max_y, max_z = float('-inf'), float('-inf'), float('-inf')
                    
                    # Read all triangles
                    # 50 bytes = 12 floats (normal + 3 vertices) + 2 bytes attribute
                    for _ in range(count):
                        data = f.read(50)
                        if len(data) < 50: break
                        
                        # Unpack 12 floats
                        floats = struct.unpack("<12f", data[:48])
                        # floats[0:3] is normal
                        # floats[3:6] is v1
                        # floats[6:9] is v2
                        # floats[9:12] is v3
                        
                        v1 = floats[3:6]
                        v2 = floats[6:9]
                        v3 = floats[9:12]
                        
                        # Update BBox
                        for v in [v1, v2, v3]:
                            if v[0] < min_x: min_x = v[0]
                            if v[0] > max_x: max_x = v[0]
                            if v[1] < min_y: min_y = v[1]
                            if v[1] > max_y: max_y = v[1]
                            if v[2] < min_z: min_z = v[2]
                            if v[2] > max_z: max_z = v[2]
                        
                        # Signed volume of tetrahedron
                        # (v1 . (v2 x v3)) / 6.0
                        cross_x = v2[1]*v3[2] - v2[2]*v3[1]
                        cross_y = v2[2]*v3[0] - v2[0]*v3[2]
                        cross_z = v2[0]*v3[1] - v2[1]*v3[0]
                        
                        dot = v1[0]*cross_x + v1[1]*cross_y + v1[2]*cross_z
                        total_vol += dot
                    
                    result["volume_mm3"] = abs(total_vol) / 6.0
                    
                    if min_x != float('inf'):
                        result["bbox"]["min"] = [min_x, min_y, min_z]
                        result["bbox"]["max"] = [max_x, max_y, max_z]
                        result["centroid"] = [
                            (min_x + max_x) / 2.0,
                            (min_y + max_y) / 2.0,
                            (min_z + max_z) / 2.0
                        ]

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/frontal_sinus_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Check file modification time vs task start
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Append timing info to JSON
# We use jq if available, otherwise simple python append
python3 -c "import json; d=json.load(open('/tmp/frontal_sinus_result.json')); d['created_during_task'] = $FILE_CREATED_DURING_TASK; json.dump(d, open('/tmp/frontal_sinus_result.json','w'))" 2>/dev/null || true

echo "=== Export Complete ==="