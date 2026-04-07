#!/bin/bash
# Export script for docker_key_recovery task

echo "=== Exporting Docker Key Recovery Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

KEY_PATH="/home/ga/Desktop/recovered_key.txt"
REPORT_PATH="/home/ga/Desktop/recovery_report.txt"

# 1. Check Key File
KEY_EXISTS="false"
SUBMITTED_KEY=""
KEY_FILE_MTIME="0"

if [ -f "$KEY_PATH" ]; then
    KEY_EXISTS="true"
    SUBMITTED_KEY=$(cat "$KEY_PATH" | tr -d '[:space:]')
    KEY_FILE_MTIME=$(stat -c %Y "$KEY_PATH" 2>/dev/null || echo "0")
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
REPORT_CONTENT_PREVIEW=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read first 1000 chars for preview/check
    REPORT_CONTENT_PREVIEW=$(head -c 1000 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Check if containers are still running (just for context)
CONTAINERS_UP=$(docker ps --format '{{.Names}}' | grep -c "keyvault-" || echo "0")

# 4. Check if files were created during task
KEY_CREATED_DURING_TASK="false"
if [ "$KEY_FILE_MTIME" -gt "$TASK_START" ]; then
    KEY_CREATED_DURING_TASK="true"
fi

REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Create result JSON
cat > /tmp/key_recovery_result.json <<EOF
{
    "task_start": $TASK_START,
    "key_exists": $KEY_EXISTS,
    "submitted_key": "$SUBMITTED_KEY",
    "key_created_during_task": $KEY_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT_PREVIEW",
    "containers_running_count": $CONTAINERS_UP,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/key_recovery_result.json"
echo "Submitted Key: $SUBMITTED_KEY"
echo "=== Export Complete ==="