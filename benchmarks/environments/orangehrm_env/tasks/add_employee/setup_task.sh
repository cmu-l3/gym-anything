#!/bin/bash
# Pre-task setup for add_employee task
# Ensures Marcus Rivera does not exist and opens PIM > Add Employee page

echo "=== Setting up add_employee task ==="

source /workspace/scripts/task_utils.sh

# Ensure OrangeHRM is reachable
wait_for_http "$ORANGEHRM_URL" 60

# Remove Marcus Rivera if already exists (from a previous run)
EXISTING=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Marcus' AND emp_lastname='Rivera' AND purged_at IS NULL LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    log "Soft-deleting existing Marcus Rivera (empNumber=$EXISTING)..."
    orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE emp_number=${EXISTING};" || true
fi

# Also purge any other non-seeded employees from previous test runs
# (employees not in EMP001-EMP020 and not the admin at emp_number=1)
orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE purged_at IS NULL AND emp_number != 1 AND employee_id NOT IN ('EMP001','EMP002','EMP003','EMP004','EMP005','EMP006','EMP007','EMP008','EMP009','EMP010','EMP011','EMP012','EMP013','EMP014','EMP015','EMP016','EMP017','EMP018','EMP019','EMP020');" 2>/dev/null || true
log "Cleaned up any non-seeded employees from prior test runs"

# Record initial employee count
INITIAL_COUNT=$(get_employee_count)
log "Initial employee count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/orangehrm_initial_employee_count.txt
chmod 666 /tmp/orangehrm_initial_employee_count.txt 2>/dev/null || true

# Navigate to PIM > Add Employee
TARGET_URL="${ORANGEHRM_URL}/web/index.php/pim/addEmployee"
ensure_orangehrm_logged_in "$TARGET_URL"

# Take screenshot to verify state
sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== add_employee task setup complete ==="
echo "Target: Add employee Marcus Rivera (EMP021)"
