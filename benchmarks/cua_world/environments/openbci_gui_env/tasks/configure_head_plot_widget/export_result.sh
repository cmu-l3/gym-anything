#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture final state screenshot (system level)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather task metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/head_plot_session.png"

# Check if the user-created screenshot exists
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT")
    OUTPUT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if OpenBCI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$EXPECTED_SCREENSHOT",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location with permissive access
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json