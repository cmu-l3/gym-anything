#!/bin/bash
# Pre-task setup for apply_leave task
# Ensures Sarah Mitchell (EMP002) exists with Annual Leave entitlement, navigates to Leave > Apply

echo "=== Setting up apply_leave task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# Get Sarah Mitchell's employee number
EMP_NUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP002' AND purged_at IS NULL LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$EMP_NUM" ]; then
    EMP_NUM=$(get_employee_empnum "Sarah" "Mitchell")
fi

if [ -z "$EMP_NUM" ]; then
    echo "ERROR: Employee Sarah Mitchell (EMP002) not found"
    exit 1
fi

log "Found Sarah Mitchell at empNumber=$EMP_NUM"

# Ensure Annual Leave type exists
LT_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Annual Leave' AND deleted=0 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$LT_ID" ]; then
    echo "ERROR: 'Annual Leave' leave type not found"
    exit 1
fi
log "Annual Leave type id=$LT_ID"

# Ensure leave entitlement exists for Sarah (add/update to 15 days if missing)
CURRENT_YEAR=$(date +%Y)
ENTITLEMENT_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_leave_entitlement WHERE emp_number=${EMP_NUM} AND leave_type_id=${LT_ID} AND deleted=0 AND to_date >= '${CURRENT_YEAR}-01-01';" 2>/dev/null | tr -d '[:space:]')
if [ "${ENTITLEMENT_COUNT:-0}" -eq 0 ]; then
    log "Adding Annual Leave entitlement for Sarah Mitchell..."
    orangehrm_db_query "INSERT INTO ohrm_leave_entitlement (emp_number, no_of_days, leave_type_id, from_date, to_date, credited_date, days_used, entitlement_type, deleted, created_by_id) VALUES (${EMP_NUM}, 15, ${LT_ID}, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1);" 2>/dev/null || true
fi

# Cancel any pending leave requests for Sarah to avoid conflicts
# Note: ohrm_leave_request has no 'deleted' column; hard-delete child records first
orangehrm_db_query "DELETE FROM ohrm_leave WHERE emp_number=${EMP_NUM};" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_leave_request WHERE emp_number=${EMP_NUM};" 2>/dev/null || true

# Calculate the next working day (Mon-Fri) for the task description
# Skip weekends since OrangeHRM won't allow leave on non-working days
NEXT_WORKDAY=$(python3 -c "
from datetime import date, timedelta
d = date.today() + timedelta(days=1)
while d.weekday() >= 5:  # 5=Sat, 6=Sun
    d += timedelta(days=1)
print(d)
" 2>/dev/null || date -d "next Monday" +%Y-%m-%d 2>/dev/null || date -d "+3 day" +%Y-%m-%d)
log "Next workday: $NEXT_WORKDAY"
echo "$NEXT_WORKDAY" > /tmp/orangehrm_leave_date.txt
chmod 666 /tmp/orangehrm_leave_date.txt 2>/dev/null || true

# Ensure leave period is configured (required for leave assignment)
LEAVE_PERIOD_DEF=$(orangehrm_db_query "SELECT value FROM hs_hr_config WHERE name='leave_period_defined';" 2>/dev/null | tr -d '[:space:]')
if [ "${LEAVE_PERIOD_DEF}" != "Yes" ]; then
    log "Configuring leave period..."
    orangehrm_db_query "INSERT INTO hs_hr_config (name, value) VALUES ('leave_period_defined', 'Yes') ON DUPLICATE KEY UPDATE value='Yes';" 2>/dev/null || true
    orangehrm_db_query "INSERT IGNORE INTO ohrm_leave_period_history (leave_period_start_month, leave_period_start_day, created_at) VALUES (1, 1, CURDATE());" 2>/dev/null || true
fi

# Navigate to Leave > Assign Leave (admin assigns leave for an employee)
TARGET_URL="${ORANGEHRM_URL}/web/index.php/leave/assignLeave"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== apply_leave task setup complete ==="
echo "Target: Apply Annual Leave for Sarah Mitchell (empNumber=$EMP_NUM) on $NEXT_WORKDAY"
echo "$EMP_NUM" > /tmp/orangehrm_leave_empnum.txt
chmod 666 /tmp/orangehrm_leave_empnum.txt 2>/dev/null || true
