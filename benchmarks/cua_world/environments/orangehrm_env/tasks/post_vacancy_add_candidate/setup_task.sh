#!/bin/bash
set -e
echo "=== Setting up post_vacancy_add_candidate task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure OrangeHRM is running and accessible
wait_for_http "$ORANGEHRM_URL" 60

# ==============================================================================
# 1. Clean up Previous State
# ==============================================================================
log "Cleaning up any existing data for this task..."

# Define target data
VACANCY_NAME="HR Manager - East Regional Office"
CANDIDATE_EMAIL="rebecca.martinez@email.com"

# Delete existing candidate if present (by email)
# ohrm_job_candidate table
orangehrm_db_query "DELETE FROM ohrm_job_candidate WHERE email='${CANDIDATE_EMAIL}';" 2>/dev/null || true

# Delete existing vacancy if present (by name)
# ohrm_job_vacancy table
orangehrm_db_query "DELETE FROM ohrm_job_vacancy WHERE name='${VACANCY_NAME}';" 2>/dev/null || true

# ==============================================================================
# 2. Ensure Dependencies Exist (Job Title & Hiring Manager)
# ==============================================================================
log "Verifying dependencies..."

# Verify 'HR Manager' job title exists
JT_ID=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='HR Manager' AND is_deleted=0 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$JT_ID" ]; then
    log "Creating 'HR Manager' job title..."
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('HR Manager', 0);"
fi

# Verify 'Sarah Johnson' exists as employee
HM_ID=$(get_employee_empnum "Sarah" "Johnson")
if [ -z "$HM_ID" ]; then
    log "Creating 'Sarah Johnson' employee for Hiring Manager role..."
    orangehrm_db_query "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id) VALUES ('Sarah', 'Johnson', 'EMP_SJ_001');"
    HM_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi
# Ensure Sarah Johnson has a User account? (Usually required for Hiring Manager dropdown in some versions, 
# but in 5.x often just being an employee is enough, or they need to be a PIM supervisor. 
# We'll assume the seed data handles the basics, but let's ensure she exists.)

log "Dependencies verified: JobTitle ID=${JT_ID}, HiringManager ID=${HM_ID}"

# ==============================================================================
# 3. Record Initial State
# ==============================================================================
INITIAL_VACANCY_COUNT=$(orangehrm_count "ohrm_job_vacancy" "status=1")
INITIAL_CANDIDATE_COUNT=$(orangehrm_count "ohrm_job_candidate" "is_deleted=0")

echo "$INITIAL_VACANCY_COUNT" > /tmp/initial_vacancy_count.txt
echo "$INITIAL_CANDIDATE_COUNT" > /tmp/initial_candidate_count.txt

# save expected HM_ID for verification
echo "$HM_ID" > /tmp/expected_hm_id.txt

# ==============================================================================
# 4. Prepare Browser
# ==============================================================================
# Log in and navigate to Dashboard
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="