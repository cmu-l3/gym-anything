#!/bin/bash
set -e

echo "=== Exporting User Manual Sections Result ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/aquatrack_manual_formatted.docx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output file exists
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if LibreOffice is still running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
    # Try to gracefully close it
    pkill -f "soffice.bin" || true
fi

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move JSON to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"