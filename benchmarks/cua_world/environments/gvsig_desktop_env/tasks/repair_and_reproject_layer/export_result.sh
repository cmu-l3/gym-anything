#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_SHP="/home/ga/gvsig_data/exports/cities_web_mercator.shp"
OUTPUT_PRJ="/home/ga/gvsig_data/exports/cities_web_mercator.prj"

# Check output file status
SHP_EXISTS="false"
SHP_SIZE="0"
SHP_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SHP" ]; then
    SHP_EXISTS="true"
    SHP_SIZE=$(stat -c %s "$OUTPUT_SHP")
    SHP_MTIME=$(stat -c %Y "$OUTPUT_SHP")
    
    if [ "$SHP_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

PRJ_EXISTS="false"
if [ -f "$OUTPUT_PRJ" ]; then
    PRJ_EXISTS="true"
fi

# Check if application was running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Create Result JSON
# We export basic file stats here, but detailed binary analysis happens in verifier.py
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shp_exists": $SHP_EXISTS,
    "prj_exists": $PRJ_EXISTS,
    "shp_size_bytes": $SHP_SIZE,
    "file_created_during_task": $CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "output_shp_path": "$OUTPUT_SHP",
    "output_prj_path": "$OUTPUT_PRJ",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export complete ==="