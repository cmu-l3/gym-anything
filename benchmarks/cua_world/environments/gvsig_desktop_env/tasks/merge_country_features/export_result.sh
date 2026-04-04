#!/bin/bash
echo "=== Exporting merge_country_features results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_SHP="/home/ga/gvsig_data/exports/sales_regions.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/sales_regions.dbf"
OUTPUT_SHX="/home/ga/gvsig_data/exports/sales_regions.shx"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0

if [ -f "$OUTPUT_SHP" ] && [ -f "$OUTPUT_DBF" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_DBF" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if gvSIG is still running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE_BYTES,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "shp_path": "$OUTPUT_SHP",
    "dbf_path": "$OUTPUT_DBF"
}
EOF

# 5. Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="