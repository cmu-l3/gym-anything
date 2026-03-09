#!/bin/bash
echo "=== Exporting intersect_rivers_countries results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect task timing info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check output file status
OUTPUT_BASE="/home/ga/gvsig_data/exports/rivers_by_country"
SHP_PATH="${OUTPUT_BASE}.shp"
DBF_PATH="${OUTPUT_BASE}.dbf"
SHX_PATH="${OUTPUT_BASE}.shx"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
SHP_SIZE="0"
SHP_MTIME="0"

if [ -f "$SHP_PATH" ]; then
    OUTPUT_EXISTS="true"
    SHP_SIZE=$(stat -c %s "$SHP_PATH" 2>/dev/null || echo "0")
    SHP_MTIME=$(stat -c %Y "$SHP_PATH" 2>/dev/null || echo "0")
    
    if [ "$SHP_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check for companion files
DBF_EXISTS=$([ -f "$DBF_PATH" ] && echo "true" || echo "false")
SHX_EXISTS=$([ -f "$SHX_PATH" ] && echo "true" || echo "false")

# 4. Check if gvSIG is still running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "dbf_exists": $DBF_EXISTS,
    "shx_exists": $SHX_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "shp_size_bytes": $SHP_SIZE,
    "shp_mtime": $SHP_MTIME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_base_path": "$OUTPUT_BASE"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="