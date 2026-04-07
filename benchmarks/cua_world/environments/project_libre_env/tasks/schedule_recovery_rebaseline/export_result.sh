#!/bin/bash
echo "=== Exporting task results ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Define expected output path
OUTPUT_PATH="/home/ga/Projects/output/schedule_recovery.xml"

# Check output file stats
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Also check if the working file was modified (agent may have saved in-place)
WORKING_FILE="/home/ga/Projects/current_task.xml"
WORKING_MODIFIED="false"
if [ -f "$WORKING_FILE" ]; then
    WORKING_MTIME=$(stat -c %Y "$WORKING_FILE" 2>/dev/null || echo "0")
    if [ "$WORKING_MTIME" -gt "$TASK_START" ]; then
        WORKING_MODIFIED="true"
    fi
fi

# Copy output file to /tmp for verifier access
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/result_project.xml
    chmod 644 /tmp/result_project.xml
elif [ "$WORKING_MODIFIED" = "true" ]; then
    # Fallback: if agent saved in-place rather than to output path
    cp "$WORKING_FILE" /tmp/result_project.xml
    chmod 644 /tmp/result_project.xml
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "working_file_modified": $WORKING_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
