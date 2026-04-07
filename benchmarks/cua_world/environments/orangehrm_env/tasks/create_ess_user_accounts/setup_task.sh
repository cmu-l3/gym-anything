#!/bin/bash
set -e
echo "=== Setting up task: create_ess_user_accounts ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OrangeHRM is accessible
# ============================================================
wait_for_http "$ORANGEHRM_URL" 60

# ============================================================
# 2. Ensure employees Lisa Andrews and David Morris exist
#    and do NOT have existing user accounts
# ============================================================
log "Ensuring employee Lisa Andrews exists..."

# Check if Lisa Andrews already exists
LISA_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE emp_firstname='Lisa' AND emp_lastname='Andrews' AND purged_at IS NULL;" | tr -d '[:space:]')

if [ "${LISA_EXISTS:-0}" -eq 0 ]; then
    log "Creating employee Lisa Andrews..."
    # Create with a dummy ID
    orangehrm_db_query "
        INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_gender, emp_birthday, emp_marital_status, emp_work_email)
        VALUES ('EMP-LA01', 'Andrews', 'Lisa', 2, '1991-03-22', 'Single', 'lisa.andrews@example.com');
    "
fi

log "Ensuring employee David Morris exists..."
DAVID_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE emp_firstname='David' AND emp_lastname='Morris' AND purged_at IS NULL;" | tr -d '[:space:]')

if [ "${DAVID_EXISTS:-0}" -eq 0 ]; then
    log "Creating employee David Morris..."
    orangehrm_db_query "
        INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_gender, emp_birthday, emp_marital_status, emp_work_email)
        VALUES ('EMP-DM01', 'Morris', 'David', 1, '1987-08-14', 'Married', 'david.morris@example.com');
    "
fi

# Remove any existing user accounts for these employees (to ensure clean state)
log "Removing any existing user accounts for Lisa Andrews and David Morris..."
orangehrm_db_query "
    DELETE FROM ohrm_user WHERE emp_number IN (
        SELECT emp_number FROM hs_hr_employee
        WHERE (emp_firstname='Lisa' AND emp_lastname='Andrews')
           OR (emp_firstname='David' AND emp_lastname='Morris')
    );
"

# Also remove by username in case of orphaned records
orangehrm_db_query "DELETE FROM ohrm_user WHERE user_name IN ('lisa.andrews', 'david.morris');"

# ============================================================
# 3. Record initial state (for verification)
# ============================================================
INITIAL_USER_COUNT=$(orangehrm_count "ohrm_user" "1=1")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# Record employee numbers
LISA_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Lisa' AND emp_lastname='Andrews' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
DAVID_EMPNUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='David' AND emp_lastname='Morris' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

# Save these to a JSON for the verifier to know the ground truth employee IDs
cat > /tmp/task_ground_truth.json << EOF
{
    "initial_user_count": $INITIAL_USER_COUNT,
    "lisa_emp_number": "$LISA_EMPNUM",
    "david_emp_number": "$DAVID_EMPNUM"
}
EOF

log "Setup: Lisa EMP=$LISA_EMPNUM, David EMP=$DAVID_EMPNUM"

# ============================================================
# 4. Log in to OrangeHRM and navigate to User Management page
# ============================================================
USER_MGMT_URL="${ORANGEHRM_URL}/web/index.php/admin/viewSystemUsers"
log "Logging into OrangeHRM and navigating to User Management..."

ensure_orangehrm_logged_in "$USER_MGMT_URL"

# Wait for the page to fully load
sleep 5

# Navigate explicitly to ensure we are on the right page
focus_firefox || true
navigate_to_url "$USER_MGMT_URL"
sleep 5

# ============================================================
# 5. Take initial screenshot
# ============================================================
take_screenshot /tmp/task_initial.png
log "Initial screenshot saved."

echo "=== Task setup complete ==="