#!/bin/bash
set -e
echo "=== Setting up configure_leave_period_start_date task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure OrangeHRM is running and accessible
wait_for_http "$ORANGEHRM_URL" 60

# 2. Reset Leave Period to Default (January 1st)
# We update the global config keys.
# Note: 'leave_period_start_month' (1=Jan) and 'leave_period_start_day'
log "Resetting leave period configuration to Jan 1st..."
orangehrm_db_query "INSERT INTO hs_hr_config (key, value) VALUES ('leave_period_start_month', '1') ON DUPLICATE KEY UPDATE value='1';" 2>/dev/null || \
orangehrm_db_query "INSERT INTO hs_hr_config (name, value) VALUES ('leave_period_start_month', '1') ON DUPLICATE KEY UPDATE value='1';" 2>/dev/null || true

orangehrm_db_query "INSERT INTO hs_hr_config (key, value) VALUES ('leave_period_start_day', '1') ON DUPLICATE KEY UPDATE value='1';" 2>/dev/null || \
orangehrm_db_query "INSERT INTO hs_hr_config (name, value) VALUES ('leave_period_start_day', '1') ON DUPLICATE KEY UPDATE value='1';" 2>/dev/null || true

# 3. Clean up leave data that might block configuration changes
# OrangeHRM often prevents changing leave period if there are existing leave requests/entitlements
# overlapping the boundary. We purge them for the task context to ensure the agent doesn't hit a validation wall.
log "Clearing existing leave data to prevent validation errors..."
orangehrm_db_query "DELETE FROM ohrm_leave_request_comment;" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_leave;" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_leave_request;" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_leave_entitlement;" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_leave_adjustment;" 2>/dev/null || true

# 4. Record Initial State
INITIAL_MONTH=$(orangehrm_db_query "SELECT value FROM hs_hr_config WHERE key='leave_period_start_month' OR name='leave_period_start_month';" 2>/dev/null | tr -d '[:space:]')
INITIAL_DAY=$(orangehrm_db_query "SELECT value FROM hs_hr_config WHERE key='leave_period_start_day' OR name='leave_period_start_day';" 2>/dev/null | tr -d '[:space:]')
echo "${INITIAL_MONTH:-1}" > /tmp/initial_month.txt
echo "${INITIAL_DAY:-1}" > /tmp/initial_day.txt

log "Initial Leave Period: Month=${INITIAL_MONTH:-1}, Day=${INITIAL_DAY:-1}"

# 5. Launch Browser and Login
# Navigate to Dashboard initially so agent has to find the path
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# 6. Capture Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="