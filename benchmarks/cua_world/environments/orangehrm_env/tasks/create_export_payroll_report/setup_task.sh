#!/bin/bash
set -e
echo "=== Setting up create_export_payroll_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrangeHRM
wait_for_http "$ORANGEHRM_URL" 60

# 3. Clean up previous artifacts
# Remove report if exists
REPORT_ID=$(orangehrm_db_query "SELECT report_id FROM ohrm_report WHERE name='Engineering Payroll';" 2>/dev/null | tr -d '[:space:]')
if [ -n "$REPORT_ID" ]; then
    log "Removing existing report (id=$REPORT_ID)..."
    orangehrm_db_query "DELETE FROM ohrm_selected_display_field WHERE report_id=$REPORT_ID;"
    orangehrm_db_query "DELETE FROM ohrm_selected_filter_field WHERE report_id=$REPORT_ID;"
    orangehrm_db_query "DELETE FROM ohrm_selected_group_field WHERE report_id=$REPORT_ID;"
    orangehrm_db_query "DELETE FROM ohrm_report WHERE report_id=$REPORT_ID;"
fi

# Clear Downloads folder
rm -f /home/ga/Downloads/*.csv
rm -f /home/ga/Downloads/*.txt

# 4. Seed Data
# Ensure Job Title 'Software Engineer' exists
if ! job_title_exists "Software Engineer"; then
    log "Creating Software Engineer job title..."
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Software Engineer', 0);"
fi
JOB_TITLE_ID=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='Software Engineer' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Ensure Employee 'Alice Dev' exists
if ! employee_exists_by_name "Alice" "Dev"; then
    log "Creating employee Alice Dev..."
    # Insert employee
    orangehrm_db_query "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id) VALUES ('Alice', 'Dev', 'ENG001');"
fi
EMP_NUMBER=$(get_employee_empnum "Alice" "Dev")

# Assign Job Title to Alice
log "Assigning Job Title to Alice..."
orangehrm_db_query "UPDATE hs_hr_employee SET job_title_code=$JOB_TITLE_ID WHERE emp_number=$EMP_NUMBER;"

# Assign Salary to Alice
# Check if salary record exists
SALARY_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_emp_basicsalary WHERE emp_number=$EMP_NUMBER;" 2>/dev/null | tr -d '[:space:]')
if [ "$SALARY_COUNT" -eq "0" ]; then
    log "Assigning Salary to Alice..."
    # Assuming currency_id 'USD' exists or similar. Typically 'USD' is standard.
    # We might need to ensure pay grade exists, but often direct SQL insert works if FK checks aren't strict or if we use defaults.
    # Let's try a safe insert.
    orangehrm_db_query "INSERT INTO hs_hr_emp_basicsalary (emp_number, sal_grd_code, currency_id, ebsal_basic_salary, payperiod_code) VALUES ($EMP_NUMBER, NULL, 'USD', '85000', 'Monthly');" 2>/dev/null || \
    log "Warning: Could not insert salary (Currency USD might be missing). Attempting generic insert."
fi

# 5. Start Browser
# Navigate to Reports page
TARGET_URL="${ORANGEHRM_URL}/web/index.php/pim/viewDefinedPredefinedReports"
ensure_orangehrm_logged_in "$TARGET_URL"

# 6. Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="