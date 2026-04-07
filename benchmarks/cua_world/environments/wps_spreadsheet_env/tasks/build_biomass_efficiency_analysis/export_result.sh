#!/bin/bash
set -euo pipefail

echo "=== Exporting Biomass Efficiency Analysis Result ==="

TARGET_FILE="/home/ga/Documents/eia923_biomass_data.xlsx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Basic file checks
OUTPUT_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

APP_RUNNING="false"
if pgrep -x "et" > /dev/null; then
    APP_RUNNING="true"
fi

# Export minimal JSON summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Use safe permission transfer
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json