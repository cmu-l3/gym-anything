#!/bin/bash
echo "=== Exporting convex_hull_cities results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_BASE="/home/ga/gvsig_data/exports/convex_hull_cities"
OUTPUT_SHP="${OUTPUT_BASE}.shp"
OUTPUT_SHX="${OUTPUT_BASE}.shx"
OUTPUT_DBF="${OUTPUT_BASE}.dbf"

# 1. Check Output Existence and Timestamps
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if App is Running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare files for verification
# We copy the shapefile components to /tmp so the verifier can copy them out
# using copy_from_env. We need read permissions.
if [ "$OUTPUT_EXISTS" == "true" ]; then
    cp "$OUTPUT_SHP" /tmp/verify_output.shp
    [ -f "$OUTPUT_SHX" ] && cp "$OUTPUT_SHX" /tmp/verify_output.shx
    [ -f "$OUTPUT_DBF" ] && cp "$OUTPUT_DBF" /tmp/verify_output.dbf
    chmod 644 /tmp/verify_output.*
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "verification_shp_path": "/tmp/verify_output.shp"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="