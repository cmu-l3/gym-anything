#!/bin/bash
set -e
echo "=== Exporting add_problem_list_entry results ==="

# Load shared utils if available, otherwise define basics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PID=$(cat /tmp/target_patient_pid.txt 2>/dev/null)
INITIAL_COUNT=$(cat /tmp/initial_issue_count.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Database Verification
# We query the issues table for the specific patient and condition
echo "Querying database for new issues..."

# Get current count
CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM issues WHERE pid=${TARGET_PID}" 2>/dev/null || echo "0")

# Fetch the specific record if it exists
# We look for records created/modified recently or just check existence since we wiped it in setup
# Note: NOSH issues table typically has columns: issue_id, pid, issue, icd, issue_date_active, issue_date_inactive
RECORD_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT JSON_OBJECT(
        'issue_id', issue_id,
        'issue', issue,
        'icd', icd,
        'date_active', issue_date_active,
        'date_inactive', issue_date_inactive
    ) FROM issues 
    WHERE pid=${TARGET_PID} 
    AND (issue LIKE '%Hypertension%' OR icd LIKE '%I10%')
    ORDER BY issue_id DESC LIMIT 1" 2>/dev/null || echo "null")

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "target_pid": "$TARGET_PID",
    "initial_issue_count": $INITIAL_COUNT,
    "current_issue_count": $CURRENT_COUNT,
    "found_record": $RECORD_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json