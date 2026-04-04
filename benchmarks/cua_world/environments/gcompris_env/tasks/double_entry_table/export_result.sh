#!/bin/bash
echo "=== Exporting Double Entry Table results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Capture final state screenshot (system captured)
take_screenshot /tmp/task_final.png

# 1. Check Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check for Agent-Created Evidence Screenshot
EVIDENCE_PATH="/home/ga/double_entry_success.png"
EVIDENCE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES="0"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    FILE_SIZE_BYTES=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    
    # Verify file was created AFTER task started
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_exists": $EVIDENCE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "app_running": $APP_RUNNING,
    "evidence_path": "$EVIDENCE_PATH"
}
EOF

# Move result to standard location with safe permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json