#!/bin/bash
# Pre-task setup for update_employee_contact task
# Resets James Anderson's work telephone to original value, navigates to contact details

echo "=== Setting up update_employee_contact task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# Verify James Anderson (EMP001) exists
EMP_NUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP001' AND purged_at IS NULL LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$EMP_NUM" ]; then
    # Try by name fallback
    EMP_NUM=$(get_employee_empnum "James" "Anderson")
fi

if [ -z "$EMP_NUM" ]; then
    echo "ERROR: Employee James Anderson (EMP001) not found in database"
    exit 1
fi

log "Found James Anderson at empNumber=$EMP_NUM"

# Reset work telephone to original value (so it's clearly different from target 646-555-9900)
orangehrm_db_query "UPDATE hs_hr_employee SET emp_work_telephone='212-555-0101' WHERE emp_number=${EMP_NUM};" 2>/dev/null || true

# Record current state
CURRENT_PHONE=$(orangehrm_db_query "SELECT emp_work_telephone FROM hs_hr_employee WHERE emp_number=${EMP_NUM};" 2>/dev/null | tr -d '[:space:]')
log "Current work telephone: ${CURRENT_PHONE:-not set}"

# Navigate to employee's contact details tab
TARGET_URL="${ORANGEHRM_URL}/web/index.php/pim/contactDetails/empNumber/${EMP_NUM}"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== update_employee_contact task setup complete ==="
echo "Target: Update James Anderson (empNumber=$EMP_NUM) work telephone to 646-555-9900"
echo "$EMP_NUM" > /tmp/orangehrm_target_empnum.txt
chmod 666 /tmp/orangehrm_target_empnum.txt 2>/dev/null || true
