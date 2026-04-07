#!/bin/bash
echo "=== Exporting CCAM procedure report results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Schema File
SCHEMA_FILE="/home/ga/ccam_schema.txt"
SCHEMA_EXISTS="false"
SCHEMA_SIZE="0"
SCHEMA_CREATED_DURING_TASK="false"

if [ -f "$SCHEMA_FILE" ]; then
    SCHEMA_EXISTS="true"
    SCHEMA_SIZE=$(stat -c%s "$SCHEMA_FILE" 2>/dev/null || echo "0")
    SCHEMA_MTIME=$(stat -c%Y "$SCHEMA_FILE" 2>/dev/null || echo "0")
    if [ "$SCHEMA_MTIME" -gt "$TASK_START" ]; then
        SCHEMA_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File
REPORT_FILE="/home/ga/ccam_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "schema_file": {
        "exists": $SCHEMA_EXISTS,
        "size_bytes": $SCHEMA_SIZE,
        "created_during_task": $SCHEMA_CREATED_DURING_TASK,
        "path": "$SCHEMA_FILE"
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "size_bytes": $REPORT_SIZE,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "path": "$REPORT_FILE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Prepare ground truth for verifier retrieval
# We copy ground truth files to /tmp/task_result_gt/ for easier bulk copy_from_env
mkdir -p /tmp/task_result_gt
cp /tmp/ground_truth/* /tmp/task_result_gt/ 2>/dev/null || true
chmod -R 644 /tmp/task_result_gt 2>/dev/null || true
chmod 755 /tmp/task_result_gt 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "Ground truth prepared in /tmp/task_result_gt"
echo "=== Export complete ==="