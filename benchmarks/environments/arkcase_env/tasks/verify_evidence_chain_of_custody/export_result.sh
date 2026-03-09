#!/bin/bash
# Export script for verify_evidence_chain_of_custody
set -e

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_PATH="/home/ga/evidence_audit_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Read Ground Truth (from hidden location)
GROUND_TRUTH_PATH="/var/lib/arkcase/ground_truth/evidence_audit.json"
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_PATH")
else
    GROUND_TRUTH="{}"
fi

# 4. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_content_base64": "$REPORT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ground_truth": $GROUND_TRUTH,
    "timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"