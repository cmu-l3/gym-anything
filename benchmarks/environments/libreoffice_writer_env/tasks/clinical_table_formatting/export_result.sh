#!/bin/bash
set -euo pipefail

echo "=== Exporting Clinical Table Result ==="

source /workspace/scripts/task_utils.sh

# Define paths
OUTPUT_FILE="/home/ga/Documents/table1_final.docx"
TASK_START_FILE="/tmp/task_start_time.txt"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Writer is still open
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

# Close LibreOffice gracefully to ensure locks are cleared
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing LibreOffice..."
    safe_xdotool ga :1 key ctrl+q || true
    sleep 1
    # Handle "Save changes?" dialog - Don't Save (agent should have saved already)
    safe_xdotool ga :1 key alt+d || true
fi

echo "=== Export complete ==="