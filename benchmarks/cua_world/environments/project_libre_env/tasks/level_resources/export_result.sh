#!/bin/bash
echo "=== Exporting level_resources task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LEVELED_FILE="/home/ga/Projects/leveled_project.xml"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output file status
OUTPUT_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED="false"
FILE_MTIME="0"

if [ -f "$LEVELED_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$LEVELED_FILE")
    FILE_MTIME=$(stat -c %Y "$LEVELED_FILE")
    
    # Check if created/modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Check if application is running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# 4. Create JSON result
# We do NOT parse the XML here; we let the python verifier do that for robustness
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_modified_during_task": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "output_path": "$LEVELED_FILE"
}
EOF

# 5. Move results to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"