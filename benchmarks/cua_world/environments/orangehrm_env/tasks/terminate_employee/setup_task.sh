#!/bin/bash
set -euo pipefail
echo "=== Setting up terminate_employee task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Ensure Database State
# ==============================================================================

# Ensure 'Resignation' termination reason exists
REASON_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_employee_terminate_reason WHERE name='Resignation';" 2>/dev/null | tr -d '[:space:]')
if [ "${REASON_COUNT:-0}" -eq 0 ]; then
    log "Creating 'Resignation' termination reason..."
    orangehrm_db_query "INSERT INTO ohrm_employee_terminate_reason (name) VALUES ('Resignation');"
fi

# Ensure Job Title 'Financial Analyst' exists (should be seeded, but verifying)
JOB_TITLE_ID=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='Financial Analyst' AND is_deleted=0 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$JOB_TITLE_ID" ]; then
    log "Creating 'Financial Analyst' job title..."
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Financial Analyst', 0);"
    JOB_TITLE_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" 2>/dev/null | tr -d '[:space:]')
fi

# Check if Marcus Reid exists
EMP_NUMBER=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Marcus' AND emp_lastname='Reid' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

if [ -n "$EMP_NUMBER" ]; then
    log "Marcus Reid found (Emp #$EMP_NUMBER). Resetting status..."
    # Reset to active state: remove termination link and ensure not purged
    orangehrm_db_query "UPDATE hs_hr_employee SET termination_id=NULL, purged_at=NULL, job_title_code=${JOB_TITLE_ID} WHERE emp_number=${EMP_NUMBER};"
    # Clean up any previous termination records for this employee to keep DB clean
    orangehrm_db_query "DELETE FROM ohrm_employee_termination_record WHERE id IN (SELECT termination_id FROM hs_hr_employee WHERE emp_number=${EMP_NUMBER});" 2>/dev/null || true
else
    log "Creating employee Marcus Reid..."
    # Insert new employee
    orangehrm_db_query "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, job_title_code) VALUES ('Marcus', 'Reid', ${JOB_TITLE_ID});"
    EMP_NUMBER=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Marcus' AND emp_lastname='Reid' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
fi

log "Target Employee: Marcus Reid (Emp Number: $EMP_NUMBER)"
echo "$EMP_NUMBER" > /tmp/target_emp_number.txt

# Record initial state for verification (should be NULL)
INITIAL_TERM_ID=$(orangehrm_db_query "SELECT termination_id FROM hs_hr_employee WHERE emp_number=${EMP_NUMBER};" 2>/dev/null | tr -d '[:space:]')
echo "${INITIAL_TERM_ID:-NULL}" > /tmp/initial_termination_id.txt

# ==============================================================================
# 2. Application Setup
# ==============================================================================

# Ensure OrangeHRM is ready
wait_for_http "$ORANGEHRM_URL" 60

# Log in and navigate to Dashboard
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# Maximize window for visibility
focus_firefox

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="