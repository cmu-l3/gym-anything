#!/bin/bash
echo "=== Exporting audit_sds_archive_report results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Check report file
REPORT_PATH="/home/ga/data_availability_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy report to /tmp for verifier access
    cp "$REPORT_PATH" /tmp/data_availability_report.txt
    chmod 666 /tmp/data_availability_report.txt
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Handle permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json