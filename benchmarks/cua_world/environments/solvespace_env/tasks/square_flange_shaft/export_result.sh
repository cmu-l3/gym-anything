#!/bin/bash
echo "=== Exporting square_flange_shaft task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/SolveSpace/square_flange_shaft.slvs"
EXPORT_STL="/tmp/task_export.stl"

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE="0"
EXTRUDE_COUNT="0"
CIRCLE_COUNT="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Analyze the .slvs file contents
    # Group.type=5100 represents an extrude group
    EXTRUDE_COUNT=$(grep -c "Group\.type=5100" "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Request.type=400 represents a circle
    CIRCLE_COUNT=$(grep -c "Request\.type=400" "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Attempt to export STL using solvespace-cli for geometric verification
    rm -f "$EXPORT_STL"
    if which solvespace-cli > /dev/null 2>&1; then
        timeout 30 solvespace-cli export-mesh "$TARGET_FILE" -o "$EXPORT_STL" >/dev/null 2>&1 || true
    fi
fi

# Analyze the STL mesh if export succeeded
STL_EXISTS="false"
STL_DATA='{"triangles": 0, "dx": 0.0, "dy": 0.0, "dz": 0.0}'

if [ -f "$EXPORT_STL" ] && [ "$(stat -c%s "$EXPORT_STL")" -gt 100 ]; then
    STL_EXISTS="true"
    
    # Parse binary STL bounding box and triangle count using python
    STL_DATA=$(python3 -c "
import struct, sys, json
try:
    with open('$EXPORT_STL', 'rb') as f:
        f.read(80)  # Skip header
        num_triangles = struct.unpack('<I', f.read(4))[0]
        if num_triangles < 1:
            print(json.dumps({'triangles': 0, 'dx': 0.0, 'dy': 0.0, 'dz': 0.0}))
            sys.exit(0)
            
        min_x = min_y = min_z = float('inf')
        max_x = max_y = max_z = float('-inf')
        
        for _ in range(num_triangles):
            data = f.read(50)
            vals = struct.unpack('<12fH', data)
            for j in range(3):
                vx, vy, vz = vals[3+j*3], vals[4+j*3], vals[5+j*3]
                min_x = min(min_x, vx); max_x = max(max_x, vx)
                min_y = min(min_y, vy); max_y = max(max_y, vy)
                min_z = min(min_z, vz); max_z = max(max_z, vz)
                
        dx, dy, dz = max_x - min_x, max_y - min_y, max_z - min_z
        print(json.dumps({'triangles': num_triangles, 'dx': dx, 'dy': dy, 'dz': dz}))
except Exception as e:
    print(json.dumps({'triangles': 0, 'dx': 0.0, 'dy': 0.0, 'dz': 0.0, 'error': str(e)}))
")
fi

# Check if application was still running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "extrude_count": $EXTRUDE_COUNT,
    "circle_count": $CIRCLE_COUNT,
    "stl_exported": $STL_EXISTS,
    "stl_data": $STL_DATA,
    "app_was_running": $APP_RUNNING
}
EOF

# Make sure it's accessible to the verifier
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="