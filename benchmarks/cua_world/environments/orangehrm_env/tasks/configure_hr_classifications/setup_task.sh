#!/bin/bash
set -e
echo "=== Setting up configure_hr_classifications task ==="

source /workspace/scripts/task_utils.sh

# Ensure OrangeHRM is running
wait_for_http "$ORANGEHRM_URL" 60

# ==============================================================================
# 1. Clean up target data (Idempotency)
#    We remove the specific items we ask the agent to create so they start fresh.
# ==============================================================================
echo "Cleaning up any existing target records..."

# Employment Status (ohrm_employment_status)
orangehrm_db_query "DELETE FROM ohrm_employment_status WHERE name IN ('Intern - Paid', 'Intern - Unpaid', 'Contractor - Remote');"

# Job Categories (ohrm_job_category)
orangehrm_db_query "DELETE FROM ohrm_job_category WHERE name IN ('Remote Engineering', 'Campus Recruitment');"

# Education (ohrm_education)
orangehrm_db_query "DELETE FROM ohrm_education WHERE name IN ('Associates Degree - IT', 'Coding Bootcamp Certificate');"

# ==============================================================================
# 2. Record Initial State (Counts)
#    Used to detect if the agent actually added records vs doing nothing.
# ==============================================================================
INIT_EMP_STATUS_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_employment_status;" | tr -d '[:space:]')
INIT_JOB_CAT_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_category;" | tr -d '[:space:]')
INIT_EDU_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_education;" | tr -d '[:space:]')

# Save initial counts to a JSON file for the exporter to read later
cat > /tmp/initial_counts.json << EOF
{
  "emp_status_count": ${INIT_EMP_STATUS_COUNT:-0},
  "job_cat_count": ${INIT_JOB_CAT_COUNT:-0},
  "edu_count": ${INIT_EDU_COUNT:-0}
}
EOF

echo "Initial counts recorded:"
cat /tmp/initial_counts.json

# ==============================================================================
# 3. Prepare Environment
# ==============================================================================
# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch browser logged in as Admin on Dashboard
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="