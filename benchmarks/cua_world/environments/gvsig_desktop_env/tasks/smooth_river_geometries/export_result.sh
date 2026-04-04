#!/bin/bash
echo "=== Exporting smooth_river_geometries results ==="

source /workspace/scripts/task_utils.sh

# Paths
INPUT_SHP="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"
OUTPUT_SHP="/home/ga/gvsig_data/exports/rivers_smooth.shp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output Existence and Timestamp
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
SHP_TYPE_CODE="-1"

if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SHP")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # 2. Check Geometry Type (Python one-liner to read SHP header)
    # Byte 32 in .shp header is the Shape Type (Little Endian Integer)
    # 3 = PolyLine, 5 = Polygon
    SHP_TYPE_CODE=$(python3 -c "import struct; f=open('$OUTPUT_SHP','rb'); f.seek(32); print(struct.unpack('<i', f.read(4))[0]); f.close()" 2>/dev/null || echo "-1")
fi

# 3. Get Input Size (Reference)
INPUT_SIZE=$(stat -c %s "$INPUT_SHP" 2>/dev/null || echo "0")

# 4. Check if App is Running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 5. Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "input_size_bytes": $INPUT_SIZE,
    "shape_type_code": $SHP_TYPE_CODE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json