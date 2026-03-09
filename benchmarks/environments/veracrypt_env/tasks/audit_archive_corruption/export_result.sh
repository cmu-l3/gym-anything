#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Audit Results ==="

REPORT_PATH="/home/ga/Documents/audit_report.csv"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILES_CREATED_DURING_TASK="false"

# Check report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    # Check timestamp
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# Check Volume 002 State (Did they fix it?)
# If they restored the header, the first 128KB should match the backup
CASE_002_PATH="/home/ga/Volumes/Evidence/case_002.hc"
BACKUP_PATH="/home/ga/Documents/Recovery/case_002_header.bk"
HEADER_RESTORED="false"

# Compare first 128KB
HEAD_VOL=$(head -c 131072 "$CASE_002_PATH" | md5sum | awk '{print $1}')
HEAD_BK=$(head -c 131072 "$BACKUP_PATH" | md5sum | awk '{print $1}')

if [ "$HEAD_VOL" == "$HEAD_BK" ]; then
    HEADER_RESTORED="true"
fi

# Take screenshot
take_screenshot /tmp/task_end.png

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "report_created_during_task": $FILES_CREATED_DURING_TASK,
    "case_002_header_restored": $HEADER_RESTORED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/audit_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/audit_result.json"
echo "=== Export Complete ==="