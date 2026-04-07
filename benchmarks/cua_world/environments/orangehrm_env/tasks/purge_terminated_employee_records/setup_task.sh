#!/bin/bash
set -e
echo "=== Setting up purge_terminated_employee_records task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for OrangeHRM to be ready
wait_for_http "$ORANGEHRM_URL" 60

# 2. Prepare Data: Clean up previous runs
log "Cleaning up previous test data..."
orangehrm_db_query "DELETE FROM hs_hr_employee WHERE employee_id IN ('PURGE001', 'KEEP001');"
orangehrm_db_query "DELETE FROM ohrm_employee_termination_record WHERE note LIKE '%Auto-Setup for Purge Task%';"

# 3. Create 'David Current' (Control - Active Employee)
log "Creating control employee 'David Current'..."
orangehrm_db_query "INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_number) VALUES ('KEEP001', 'Current', 'David', 9001);"

# 4. Create 'David Obsolete' (Target - To be Terminated)
log "Creating target employee 'David Obsolete'..."
orangehrm_db_query "INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_number) VALUES ('PURGE001', 'Obsolete', 'David', 9002);"

# 5. Terminate 'David Obsolete'
# Get a valid termination reason ID (usually 1='Contract Not Renewed' or similar in default seed)
REASON_ID=$(orangehrm_db_query "SELECT id FROM ohrm_employee_terminate_reason LIMIT 1;" | tr -d '[:space:]')
if [ -z "$REASON_ID" ]; then
    log "Creating termination reason..."
    orangehrm_db_query "INSERT INTO ohrm_employee_terminate_reason (name) VALUES ('Other');"
    REASON_ID=$(orangehrm_db_query "SELECT id FROM ohrm_employee_terminate_reason WHERE name='Other' LIMIT 1;" | tr -d '[:space:]')
fi

# Create termination record
log "Terminating 'David Obsolete'..."
orangehrm_db_query "INSERT INTO ohrm_employee_termination_record (reason_id, termination_date, note) VALUES (${REASON_ID}, CURDATE(), 'Auto-Setup for Purge Task');"
TERM_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')

# Link termination to employee
orangehrm_db_query "UPDATE hs_hr_employee SET termination_id=${TERM_ID} WHERE emp_number=9002;"

# 6. Record Initial State (Anti-Gaming)
INITIAL_TARGET_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE employee_id='PURGE001' AND purged_at IS NULL;" | tr -d '[:space:]')
INITIAL_CONTROL_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE employee_id='KEEP001' AND purged_at IS NULL;" | tr -d '[:space:]')

echo "$INITIAL_TARGET_COUNT" > /tmp/initial_target_count.txt
echo "$INITIAL_CONTROL_COUNT" > /tmp/initial_control_count.txt
date +%s > /tmp/task_start_time.txt

log "Initial State: Target Count=$INITIAL_TARGET_COUNT, Control Count=$INITIAL_CONTROL_COUNT"

# 7. Start Browser and Login
# Maintenance module is usually accessed from the dashboard or "More" menu
TARGET_URL="${ORANGEHRM_URL}/web/index.php/dashboard/index"
ensure_orangehrm_logged_in "$TARGET_URL"

# 8. Capture Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="