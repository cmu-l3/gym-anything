#!/bin/bash
# Export script for Network Incident HAR Capture task
set -e

echo "=== Exporting task results ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HAR_PATH="/home/ga/Desktop/incident_trace.har"

# 1. Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check HAR file status
HAR_EXISTS="false"
HAR_SIZE="0"
HAR_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$HAR_PATH" ]; then
    HAR_EXISTS="true"
    HAR_SIZE=$(stat -c %s "$HAR_PATH" 2>/dev/null || echo "0")
    HAR_MTIME=$(stat -c %Y "$HAR_PATH" 2>/dev/null || echo "0")
    
    if [ "$HAR_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy HAR file to /tmp for easier extraction by verifier
    cp "$HAR_PATH" /tmp/exported_trace.har
    chmod 666 /tmp/exported_trace.har
fi

# 3. Check if Edge is still running
APP_RUNNING=$(pgrep -f "microsoft-edge" > /dev/null && echo "true" || echo "false")

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "har_exists": $HAR_EXISTS,
    "har_path": "$HAR_PATH",
    "har_size_bytes": $HAR_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="