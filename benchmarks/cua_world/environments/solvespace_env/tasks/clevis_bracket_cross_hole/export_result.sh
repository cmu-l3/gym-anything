#!/bin/bash
echo "=== Exporting clevis_bracket_cross_hole task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SLVS_PATH="/home/ga/Documents/SolveSpace/clevis_bracket.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/clevis_bracket.stl"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
SLVS_EXISTS="false"
STL_EXISTS="false"
SLVS_CREATED="false"
STL_CREATED="false"
DIFFERENCE_USED="false"
GROUP_COUNT="0"

if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED="true"
    fi
    # Check for Boolean Difference operation in SolveSpace file
    if grep -q "Group.meshCombine=1" "$SLVS_PATH"; then
        DIFFERENCE_USED="true"
    fi
    # Count the number of groups created
    GROUP_COUNT=$(grep -c "AddGroup" "$SLVS_PATH" 2>/dev/null || echo "0")
fi

if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED="true"
    fi
fi

# Extract STL Geometry using a fast embedded Python script (binary STL parser)
STL_ANALYSIS=$(python3 - << 'EOF'
import os, struct, json

stl_path = "/home/ga/Documents/SolveSpace/clevis_bracket.stl"
res = {"volume": 0.0, "bbox": [0.0, 0.0, 0.0], "valid": False, "triangles": 0, "error": ""}

if os.path.exists(stl_path) and os.path.getsize(stl_path) > 84:
    try:
        with open(stl_path, 'rb') as f:
            header = f.read(80)
            # Binary STL uses an 80-byte header followed by a 4-byte uint32 for triangle count
            num_tris_tuple = struct.unpack('<I', f.read(4))
            num_tris = num_tris_tuple[0]
            
            # Verify file size matches expected size for declared triangle count
            expected_size = 84 + num_tris * 50
            if os.path.getsize(stl_path) >= expected_size and num_tris > 0:
                res["valid"] = True
                res["triangles"] = num_tris
                min_v = [float('inf')] * 3
                max_v = [float('-inf')] * 3
                vol = 0.0
                
                # Parse each triangle (50 bytes each)
                for _ in range(num_tris):
                    data = struct.unpack('<12fH', f.read(50))
                    v1, v2, v3 = data[3:6], data[6:9], data[9:12]
                    
                    for i in range(3):
                        min_v[i] = min(min_v[i], v1[i], v2[i], v3[i])
                        max_v[i] = max(max_v[i], v1[i], v2[i], v3[i])
                    
                    # Calculate signed volume of the tetrahedron to get total mesh volume
                    v321 = v3[0]*v2[1]*v1[2]
                    v231 = v2[0]*v3[1]*v1[2]
                    v312 = v3[0]*v1[1]*v2[2]
                    v132 = v1[0]*v3[1]*v2[2]
                    v213 = v2[0]*v1[1]*v3[2]
                    v123 = v1[0]*v2[1]*v3[2]
                    vol += (-v321 + v231 + v312 - v132 - v213 + v123) / 6.0
                
                res["volume"] = abs(vol)
                res["bbox"] = [max_v[i] - min_v[i] for i in range(3)]
            else:
                res["error"] = "Invalid STL file size or triangle count."
    except Exception as e:
        res["error"] = str(e)
else:
    res["error"] = "File missing or too small to be a valid binary STL."

print(json.dumps(res))
EOF
)

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created": $SLVS_CREATED,
    "stl_exists": $STL_EXISTS,
    "stl_created": $STL_CREATED,
    "difference_used": $DIFFERENCE_USED,
    "group_count": $GROUP_COUNT,
    "stl_analysis": $STL_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="