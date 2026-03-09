#!/bin/bash
set -e
echo "=== Exporting Redraw Grid Pattern results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record basic task info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check the evidence file (Screenshot provided by agent)
EVIDENCE_PATH="/home/ga/redraw_complete.png"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$EVIDENCE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: File must be modified AFTER task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if GCompris is still running (or was running)
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture system-level final screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_file_exists": $FILE_EXISTS,
    "evidence_file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="