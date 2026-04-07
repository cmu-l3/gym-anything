#!/bin/bash
echo "=== Exporting purge_terminated_employee_records result ==="

source /workspace/scripts/task_utils.sh

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Target Employee (Should be GONE)
# We check 'purged_at IS NULL'. If the record is physically deleted, count is 0. 
# If soft deleted (purged_at set), count is 0. Both satisfy the requirement.
TARGET_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE employee_id='PURGE001' AND purged_at IS NULL;" | tr -d '[:space:]')

# 2. Check Control Employee (Should EXIST)
CONTROL_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE employee_id='KEEP001' AND purged_at IS NULL;" | tr -d '[:space:]')

# 3. Check App State
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_target_count": ${TARGET_COUNT:-1},
    "final_control_count": ${CONTROL_COUNT:-0},
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="