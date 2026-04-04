#!/bin/bash
echo "=== Exporting generate_country_bounding_boxes results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_SHP="/home/ga/gvsig_data/exports/country_bboxes.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/country_bboxes.dbf"
OUTPUT_SHX="/home/ga/gvsig_data/exports/country_bboxes.shx"

# 1. Check Output Files
SHP_EXISTS="false"
DBF_EXISTS="false"
SHP_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SHP" ]; then
    SHP_EXISTS="true"
    SHP_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    # Anti-gaming timestamp check
    FILE_TIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_DBF" ]; then
    DBF_EXISTS="true"
fi

# 2. Check Application State
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_shp_exists": $SHP_EXISTS,
    "output_dbf_exists": $DBF_EXISTS,
    "output_shx_exists": $([ -f "$OUTPUT_SHX" ] && echo "true" || echo "false"),
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "shp_size_bytes": $SHP_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# 5. Prepare Output Files for Copying (if they exist)
# We leave them in place; the verifier will use copy_from_env to fetch them
if [ "$SHP_EXISTS" = "true" ]; then
    echo "Output files found at $OUTPUT_SHP"
    ls -l "$OUTPUT_SHP" "$OUTPUT_DBF"
else
    echo "Output files NOT found"
fi

echo "=== Export complete ==="