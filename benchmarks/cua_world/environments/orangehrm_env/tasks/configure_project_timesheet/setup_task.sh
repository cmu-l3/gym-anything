#!/bin/bash
set -e
echo "=== Setting up configure_project_timesheet task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrangeHRM is ready
wait_for_http "$ORANGEHRM_URL" 60

# 1. Clean up previous run data (if any)
# Delete customer 'Midwest Energy Cooperative' (cascades to projects/activities usually, but we do explicit cleanup)
echo "Cleaning up old data..."
CUST_ID=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='Midwest Energy Cooperative' AND is_deleted=0 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -n "$CUST_ID" ]; then
    orangehrm_db_query "UPDATE ohrm_customer SET is_deleted=1 WHERE customer_id=${CUST_ID};"
    # Also clean projects associated with this customer
    orangehrm_db_query "UPDATE ohrm_project SET is_deleted=1 WHERE customer_id=${CUST_ID};"
fi

# 2. Ensure Employee 'Ethan Davis' exists
# The env setup script says it seeds him, but we verify/create to be robust.
ETHAN_ID=$(get_employee_empnum "Ethan" "Davis")
if [ -z "$ETHAN_ID" ]; then
    echo "Creating employee Ethan Davis..."
    # Insert job title 'Operations Manager' if needed
    JT_ID=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='Operations Manager' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$JT_ID" ]; then
         orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Operations Manager', 0);"
         JT_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
    fi
    
    # Insert Employee
    orangehrm_db_query "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, job_title_code) VALUES ('Ethan', 'Davis', ${JT_ID});"
    ETHAN_ID=$(get_employee_empnum "Ethan" "Davis")
    
    # Create User account for him (optional for this task as we log in as Admin, but good practice)
    # user_role_id 1=Admin, 2=ESS. Ethan is ESS.
    # We won't strictly need his login, just his existence for the Admin to file time for him.
fi
echo "Ethan Davis Emp Number: $ETHAN_ID"
echo "$ETHAN_ID" > /tmp/target_emp_number.txt

# 3. Clean up any existing timesheets for Ethan for the CURRENT week to ensure clean slate
# Calculate start of current week (Monday)
# MySQL's WEEK() mode 3 starts Monday.
CURRENT_DATE=$(date +%Y-%m-%d)
echo "Current date: $CURRENT_DATE"

# Find timesheet for this week and delete it
# ohrm_timesheet structure: timesheet_id, state, start_date, end_date, emp_number
# We'll just delete any timesheet for this employee that covers today
orangehrm_db_query "DELETE FROM ohrm_timesheet WHERE emp_number=${ETHAN_ID} AND '${CURRENT_DATE}' BETWEEN start_date AND end_date;"

# 4. Log in and navigate to Dashboard
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="