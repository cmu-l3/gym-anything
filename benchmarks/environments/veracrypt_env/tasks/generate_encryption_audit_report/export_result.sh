#!/bin/bash
# export_result.sh for generate_encryption_audit_report
echo "=== Exporting encryption audit report result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/encryption_audit_report.json"
RESULT_JSON_PATH="/tmp/task_result.json"

# Check report file
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check mounted volumes (should be 0 for full points)
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
MOUNTED_COUNT=0
if echo "$MOUNT_LIST" | grep -q "^[0-9]"; then
    MOUNTED_COUNT=$(echo "$MOUNT_LIST" | grep -c "^[0-9]" 2>/dev/null || echo "0")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_size": $REPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "mounted_volumes_count": $MOUNTED_COUNT,
    "mount_list_output": "$(echo "$MOUNT_LIST" | sed 's/"/\\"/g' | tr '\n' ' ')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
write_result_json "$RESULT_JSON_PATH" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_JSON_PATH"
echo "=== Export complete ==="