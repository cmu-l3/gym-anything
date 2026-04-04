#!/bin/bash
echo "=== Exporting extract_kenya_utm_projection result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_BASE="/home/ga/gvsig_data/exports/kenya_utm"
OUTPUT_SHP="${OUTPUT_BASE}.shp"
OUTPUT_PRJ="${OUTPUT_BASE}.prj"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and stats
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
PRJ_CONTENT=""

if [ -f "$OUTPUT_SHP" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_PRJ" ]; then
    PRJ_CONTENT=$(cat "$OUTPUT_PRJ")
fi

# Create result JSON
# We include the paths so the verifier knows what to copy
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "prj_content": "$PRJ_CONTENT",
    "output_shp_path": "$OUTPUT_SHP",
    "output_shx_path": "${OUTPUT_BASE}.shx",
    "output_dbf_path": "${OUTPUT_BASE}.dbf",
    "output_prj_path": "${OUTPUT_BASE}.prj",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="