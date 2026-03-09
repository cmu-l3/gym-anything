#!/bin/bash
# export_result.sh - Syllabus Accessibility Task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output file exists
OUTPUT_PATH="/home/ga/Documents/CS101_Syllabus_Accessible.docx"
OUTPUT_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_TIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MODIFIED_TIME=$(stat -c %Y "$OUTPUT_PATH")
    echo "Output file found: $OUTPUT_PATH ($FILE_SIZE bytes)"
else
    echo "Output file NOT found: $OUTPUT_PATH"
fi

# 3. Check start time for modification verification
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_NEWLY_CREATED="false"

if [ "$OUTPUT_EXISTS" = "true" ] && [ "$FILE_MODIFIED_TIME" -gt "$TASK_START_TIME" ]; then
    FILE_NEWLY_CREATED="true"
fi

# 4. Check if LibreOffice is still running
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create basic result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_size": $FILE_SIZE,
    "file_newly_created": $FILE_NEWLY_CREATED,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date +%s)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

# Close Writer gracefully
echo "Closing LibreOffice Writer..."
if [ "$APP_RUNNING" = "true" ]; then
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    # Handle "Save changes?" dialog - Don't Save (agent should have saved already)
    safe_xdotool ga :1 key alt+d 2>/dev/null || true
fi

echo "=== Export Complete ==="