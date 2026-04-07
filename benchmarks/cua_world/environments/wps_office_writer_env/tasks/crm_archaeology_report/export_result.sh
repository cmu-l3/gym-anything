#!/bin/bash
set -euo pipefail

echo "=== Exporting CRM Archaeology Report Result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot BEFORE closing application
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/results/phase_i_report_formatted.docx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Securely copy file to /tmp for verification processing
    cp "$OUTPUT_PATH" /tmp/phase_i_report_formatted.docx
    chmod 666 /tmp/phase_i_report_formatted.docx
fi

APP_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

# Save metadata to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "initial_screenshot": "/tmp/task_initial_state.png",
    "final_screenshot": "/tmp/task_final_state.png"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Gracefully close WPS Writer
echo "Closing WPS Writer..."
if [ "$APP_RUNNING" = "true" ]; then
    DISPLAY=:1 wmctrl -c "WPS Writer" 2>/dev/null || true
    sleep 2
    pkill -f "wps" 2>/dev/null || true
fi

echo "=== Export Complete ==="