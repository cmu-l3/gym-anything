#!/bin/bash
echo "=== Exporting create_swing_shift_calendar results ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output file details
OUTPUT_FILE="/home/ga/Projects/swing_shift_project.xml"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Verify file was modified/created AFTER task started
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if App is still running
APP_RUNNING="false"
if pgrep -f "projectlibre" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
# Using a temp file to avoid permission issues during write
TEMP_JSON=$(mktemp)
cat <<EOF > "$TEMP_JSON"
{
  "output_exists": $OUTPUT_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "file_size": $FILE_SIZE,
  "app_running": $APP_RUNNING,
  "output_path": "$OUTPUT_FILE"
}
EOF

# Move to final location (readable by verifier)
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"