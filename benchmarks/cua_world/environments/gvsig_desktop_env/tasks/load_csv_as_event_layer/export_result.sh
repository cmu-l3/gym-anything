#!/bin/bash
echo "=== Exporting load_csv_as_event_layer results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/gvsig_data/exports"
SHP_FILE="$EXPORT_DIR/earthquakes.shp"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the shapefile if it exists
FILE_EXISTS="false"
FILE_SIZE="0"
FEATURE_COUNT="0"
GEOMETRY_TYPE="unknown"
FILE_CREATED_DURING_TASK="false"

if [ -f "$SHP_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$SHP_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$SHP_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Try to use ogrinfo to get metadata (if installed in the container)
    # The environment has python3, so we can use a small python script if ogrinfo is missing
    # But let's check for ogrinfo first (common in GIS envs)
    if command -v ogrinfo >/dev/null 2>&1; then
        INFO=$(ogrinfo -so -al "$SHP_FILE" 2>/dev/null)
        FEATURE_COUNT=$(echo "$INFO" | grep "Feature Count" | cut -d: -f2 | tr -d ' ')
        GEOMETRY_TYPE=$(echo "$INFO" | grep "Geometry:" | cut -d: -f2 | tr -d ' ')
    else
        # Fallback: Use simple hexdump or python to check SHP header
        # Byte 32 (0x20) is shape type: 1=Point, 3=PolyLine, 5=Polygon
        # Bytes 24-27 is file length in 16-bit words
        # This is a bit complex for bash, so we'll use a python one-liner for basic check
        PYTHON_SCRIPT="
import struct
import os
try:
    with open('$SHP_FILE', 'rb') as f:
        # Read file code (should be 9994)
        f.seek(0)
        file_code = struct.unpack('>I', f.read(4))[0]
        # Read shape type at offset 32
        f.seek(32)
        shape_type = struct.unpack('<I', f.read(4))[0]
        
        # Approximate feature count estimation (file size - header) / avg record size
        # This is unreliable, so we might return -1 to signal verifier to do the work
        print(f'{shape_type}')
except:
    print('error')
"
        SHAPE_TYPE_CODE=$(python3 -c "$PYTHON_SCRIPT" 2>/dev/null)
        if [ "$SHAPE_TYPE_CODE" == "1" ]; then
            GEOMETRY_TYPE="Point"
        elif [ "$SHAPE_TYPE_CODE" == "3" ]; then
            GEOMETRY_TYPE="Line String"
        elif [ "$SHAPE_TYPE_CODE" == "5" ]; then
            GEOMETRY_TYPE="Polygon"
        fi
        
        # We'll leave exact feature count to the host verifier which can have better tools
        FEATURE_COUNT="-1"
    fi
fi

# 3. Create Result JSON
# We include paths so the verifier knows where to look
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "geometry_type_internal": "$GEOMETRY_TYPE",
    "feature_count_internal": "$FEATURE_COUNT",
    "output_path": "$SHP_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="