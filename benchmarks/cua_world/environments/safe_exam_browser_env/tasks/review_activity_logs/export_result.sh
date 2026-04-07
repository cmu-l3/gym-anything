#!/bin/bash
set -euo pipefail

echo "=== Exporting review_activity_logs results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/final_screenshot.png

# 2. Extract timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Process report file
REPORT_PATH="/home/ga/Documents/activity_audit.txt"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Copy file to a safe temp location for the verifier to read
    cp "$REPORT_PATH" /tmp/activity_audit_submitted.txt
    chmod 644 /tmp/activity_audit_submitted.txt
fi

# 4. Check for current database activity (to prove agent did something)
LOG_TABLE=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth_activity.json')).get('table_used', 'user_log'))" 2>/dev/null || echo "user_log")
CURRENT_TOTAL=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM $LOG_TABLE;" 2>/dev/null | tr -d '[:space:]' || echo "0")

# 5. Build export JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "current_total_activities": ${CURRENT_TOTAL:-0},
    "screenshot_path": "/tmp/final_screenshot.png"
}
EOF
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json