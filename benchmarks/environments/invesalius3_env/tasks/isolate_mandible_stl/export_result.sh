#!/bin/bash
echo "=== Exporting isolate_mandible_stl result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_PATH="/home/ga/Documents/mandible.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Run python script to analyze STL geometry (bounds and volume)
# We calculate the Axis-Aligned Bounding Box (AABB) and signed volume.
# Z-span is critical: Mandible is much shorter than full skull.
python3 << 'PYEOF' > /tmp/stl_analysis.json
import struct
import math
import json
import sys

filepath = "/home/ga/Documents/mandible.stl"
result = {
    "valid_stl": False,
    "triangle_count": 0,
    "z_min": 0.0,
    "z_max": 0.0,
    "z_span": 0.0,
    "volume_mm3": 0.0,
    "error": ""
}

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        file_size = os.path.getsize(filepath)
        if file_size < 84:
            result["error"] = "File too small"
        else:
            with open(filepath, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                count = struct.unpack("<I", count_bytes)[0]
                
                # Basic binary STL size check
                expected_size = 84 + (count * 50)
                if file_size != expected_size:
                    # Might be ASCII or corrupt, but we strictly asked for binary usually
                    # However, let's try to proceed if size is close or just parse what we can
                    pass

                result["triangle_count"] = count
                
                if count > 0:
                    min_z = float('inf')
                    max_z = float('-inf')
                    total_vol = 0.0
                    
                    # Read triangles
                    for _ in range(count):
                        # 50 bytes: Normal(12) + V1(12) + V2(12) + V3(12) + Attr(2)
                        data = f.read(50)
                        if len(data) < 50:
                            break
                            
                        # Unpack vertices (little-endian floats)
                        # Offset 12 starts V1
                        v1 = struct.unpack("<3f", data[12:24])
                        v2 = struct.unpack("<3f", data[24:36])
                        v3 = struct.unpack("<3f", data[36:48])
                        
                        # Update bounds
                        for v in [v1, v2, v3]:
                            if v[2] < min_z: min_z = v[2]
                            if v[2] > max_z: max_z = v[2]
                            
                        # Signed volume of tetrahedron relative to origin
                        # Vol = (1/6) * dot(v1, cross(v2, v3))
                        # cross_x = v2[1]*v3[2] - v2[2]*v3[1]
                        # cross_y = v2[2]*v3[0] - v2[0]*v3[2]
                        # cross_z = v2[0]*v3[1] - v2[1]*v3[0]
                        
                        cross_x = v2[1]*v3[2] - v2[2]*v3[1]
                        cross_y = v2[2]*v3[0] - v2[0]*v3[2]
                        cross_z = v2[0]*v3[1] - v2[1]*v3[0]
                        
                        det = v1[0]*cross_x + v1[1]*cross_y + v1[2]*cross_z
                        total_vol += det

                    result["z_min"] = min_z
                    result["z_max"] = max_z
                    result["z_span"] = max_z - min_z
                    result["volume_mm3"] = abs(total_vol) / 6.0
                    result["valid_stl"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON
cat << EOF > /tmp/task_result.json
{
    "file_exists": $FILE_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "stl_analysis": $(cat /tmp/stl_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="