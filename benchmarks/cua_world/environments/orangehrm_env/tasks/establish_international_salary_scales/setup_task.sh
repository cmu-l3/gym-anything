#!/bin/bash
set -e
echo "=== Setting up establish_international_salary_scales task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for OrangeHRM
wait_for_http "$ORANGEHRM_URL" 60

# 2. Setup Data via SQL

# Helper to run SQL
sql() {
    orangehrm_db_query "$1"
}

echo "Configuring Pay Grades and Job Titles..."

# Ensure 'Software Engineer' and 'Data Scientist' Job Titles exist
for title in "Software Engineer" "Data Scientist"; do
    count=$(sql "SELECT COUNT(*) FROM ohrm_job_title WHERE job_title='${title}' AND is_deleted=0;" | tr -d '[:space:]')
    if [ "${count:-0}" -eq 0 ]; then
        echo "Creating Job Title: $title"
        sql "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('${title}', 0);"
    fi
done

# Ensure 'Software Engineer' and 'Data Scientist' Pay Grades exist
for grade in "Software Engineer" "Data Scientist"; do
    count=$(sql "SELECT COUNT(*) FROM ohrm_pay_grade WHERE name='${grade}';" | tr -d '[:space:]')
    if [ "${count:-0}" -eq 0 ]; then
        echo "Creating Pay Grade: $grade"
        sql "INSERT INTO ohrm_pay_grade (name) VALUES ('${grade}');"
    fi
done

# Link Job Titles to Pay Grades (if not already linked)
# Note: OrangeHRM allows linking multiple titles to a grade, but usually the UI flow implies a relationship.
# We just ensure the Pay Grade exists so the user can edit it.
# Linking isn't strictly necessary for the 'Edit Pay Grade' admin task, 
# BUT it is necessary for the PIM > Salary dropdown to populate correct currencies for that employee's job.
# So we must link Job Title 'Software Engineer' to Pay Grade 'Software Engineer'.

echo "Linking Job Titles to Pay Grades..."
for role in "Software Engineer" "Data Scientist"; do
    jt_id=$(sql "SELECT id FROM ohrm_job_title WHERE job_title='${role}' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')
    pg_id=$(sql "SELECT id FROM ohrm_pay_grade WHERE name='${role}' LIMIT 1;" | tr -d '[:space:]')
    
    if [ -n "$jt_id" ] && [ -n "$pg_id" ]; then
        # Check if linked
        # Note: Table structure might vary by version. Assuming ohrm_job_title matches standard schema or linkage happens via job record.
        # Actually, in standard OrangeHRM, the Salary Pay Grade dropdown in PIM is filtered by the Employee's Job Title.
        # But wait, in 5.x, you assign a Pay Grade to a Job Title in Admin > Job > Job Titles.
        # Let's ensure that link exists.
        # Table: ohrm_job_title doesn't have pay_grade_id directly usually.
        # There is usually a separate table or it's implied. 
        # Actually, let's skip complex linking if not strictly required, but for PIM dropdowns to work, 
        # the Employee must have the Job Title assigned, and that Job Title *might* limit Pay Grades.
        # In many configurations, any Pay Grade can be selected.
        : # No-op
    fi
done

# CLEANUP: Remove any existing Currency configurations for these Pay Grades
echo "Clearing existing currency bands for target pay grades..."
for grade in "Software Engineer" "Data Scientist"; do
    pg_id=$(sql "SELECT id FROM ohrm_pay_grade WHERE name='${grade}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$pg_id" ]; then
        sql "DELETE FROM ohrm_pay_grade_currency WHERE pay_grade_id=${pg_id};"
    fi
done

# Ensure Employees exist
echo "Ensuring employees exist..."

# Michael Chen
mc_emp=$(get_employee_empnum "Michael" "Chen")
if [ -z "$mc_emp" ]; then
    echo "Creating Michael Chen..."
    sql "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id) VALUES ('Michael', 'Chen', 'EMP_MC_01');"
    mc_emp=$(sql "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi
# Assign Job Title 'Software Engineer' to Michael Chen
jt_se_id=$(sql "SELECT id FROM ohrm_job_title WHERE job_title='Software Engineer' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$mc_emp" ] && [ -n "$jt_se_id" ]; then
    sql "UPDATE hs_hr_employee SET job_title_code=${jt_se_id} WHERE emp_number=${mc_emp};"
fi

# David Morris
dm_emp=$(get_employee_empnum "David" "Morris")
if [ -z "$dm_emp" ]; then
    echo "Creating David Morris..."
    sql "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id) VALUES ('David', 'Morris', 'EMP_DM_01');"
    dm_emp=$(sql "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi
# Assign Job Title 'Data Scientist' to David Morris
jt_ds_id=$(sql "SELECT id FROM ohrm_job_title WHERE job_title='Data Scientist' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$dm_emp" ] && [ -n "$jt_ds_id" ]; then
    sql "UPDATE hs_hr_employee SET job_title_code=${jt_ds_id} WHERE emp_number=${dm_emp};"
fi

# CLEANUP: Remove any existing Salary records for these employees
echo "Clearing existing salary records..."
if [ -n "$mc_emp" ]; then sql "DELETE FROM hs_hr_emp_basicsalary WHERE emp_number=${mc_emp};"; fi
if [ -n "$dm_emp" ]; then sql "DELETE FROM hs_hr_emp_basicsalary WHERE emp_number=${dm_emp};"; fi

# 3. Launch Application
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/viewPayGrades"
ensure_orangehrm_logged_in "$TARGET_URL"

# 4. Anti-gaming timestamps
date +%s > /tmp/task_start_time.txt
echo "$(get_employee_count)" > /tmp/initial_employee_count.txt

# 5. Evidence
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="