#!/bin/bash
echo "=== Exporting furlough_administrative_execution result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

log "Querying database for task verification..."

# 1. Check if Status exists
STATUS_EXISTS="false"
STATUS_ID=$(sentrifugo_db_query "SELECT id FROM main_employmentstatus WHERE statusname='Furloughed - Unpaid' AND isactive=1 LIMIT 1" | tr -d '[:space:]')
if [ -n "$STATUS_ID" ]; then
    STATUS_EXISTS="true"
fi

# 2. Check Employee Assignments (only if status exists)
EMP008_STATUS="None"
EMP011_STATUS="None"
EMP014_STATUS="None"
EMP017_STATUS="None"

get_emp_status() {
    local empid="$1"
    local st
    st=$(sentrifugo_db_query "SELECT es.statusname FROM main_users u JOIN main_employmentstatus es ON u.employment_status_id=es.id WHERE u.employeeId='${empid}' LIMIT 1" | tr -d '\n' | tr -d '\r')
    if [ -n "$st" ]; then
        echo "$st"
    else
        echo "None"
    fi
}

EMP008_STATUS=$(get_emp_status "EMP008")
EMP011_STATUS=$(get_emp_status "EMP011")
EMP014_STATUS=$(get_emp_status "EMP014")
EMP017_STATUS=$(get_emp_status "EMP017")

# 3. Check Leave Type state
ANNUAL_LEAVE_ACTIVE=$(sentrifugo_db_query "SELECT isactive FROM main_employeeleavetypes WHERE leavetype='Annual Leave' LIMIT 1" | tr -d '[:space:]')
if [ -z "$ANNUAL_LEAVE_ACTIVE" ]; then
    ANNUAL_LEAVE_ACTIVE="null"
fi

# 4. Check Announcement
ANNOUNCEMENT_EXISTS="false"
ANN_ID=$(sentrifugo_db_query "SELECT id FROM main_announcements WHERE title='Plant Operations Pause' AND isactive=1 LIMIT 1" | tr -d '[:space:]')
if [ -n "$ANN_ID" ]; then
    ANNOUNCEMENT_EXISTS="true"
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/furlough_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "status_created": $STATUS_EXISTS,
    "employee_statuses": {
        "EMP008": "$EMP008_STATUS",
        "EMP011": "$EMP011_STATUS",
        "EMP014": "$EMP014_STATUS",
        "EMP017": "$EMP017_STATUS"
    },
    "annual_leave_active_flag": $ANNUAL_LEAVE_ACTIVE,
    "announcement_published": $ANNOUNCEMENT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move safely to final location
rm -f /tmp/furlough_task_result.json 2>/dev/null || sudo rm -f /tmp/furlough_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/furlough_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/furlough_task_result.json
chmod 666 /tmp/furlough_task_result.json 2>/dev/null || sudo chmod 666 /tmp/furlough_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Database verification data exported to /tmp/furlough_task_result.json"
cat /tmp/furlough_task_result.json
echo "=== Export complete ==="