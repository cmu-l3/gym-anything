#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up correct_personal_data_discrepancies task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrangeHRM to be ready
wait_for_http "$ORANGEHRM_URL" 60

# 3. Seed "Bad Data" Employees
# We delete them first to ensure a clean state if re-running
echo "Seeding employees with incorrect placeholder data..."

# Prepare SQL for seeding
# Note: We rely on standard nationalities usually present. 
# 'American' is usually ID 1 or near top. We'll query for 'American' to get a valid ID for the placeholder.
USA_ID=$(orangehrm_db_query "SELECT id FROM ohrm_nationality WHERE name = 'American' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
USA_ID=${USA_ID:-1} # Default to 1 if not found

cat > /tmp/seed_discrepancy_employees.sql <<SQL
-- Delete if exist
DELETE FROM hs_hr_employee WHERE emp_firstname IN ('Dario', 'Mei', 'Sven') AND emp_lastname IN ('Rossi', 'Chen', 'Olson');

-- Insert Dario Rossi (Placeholder: 1970-01-01, Single, American)
INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, emp_birthday, marital_status, emp_gender, nation_code)
VALUES ('Dario', 'Rossi', '1970-01-01', 'Single', 1, ${USA_ID});

-- Insert Mei Chen (Placeholder: 1970-01-01, Married, American)
INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, emp_birthday, marital_status, emp_gender, nation_code)
VALUES ('Mei', 'Chen', '1970-01-01', 'Married', 2, ${USA_ID});

-- Insert Sven Olson (Placeholder: 1970-01-01, Single, American)
INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, emp_birthday, marital_status, emp_gender, nation_code, emp_dri_lice_exp_date)
VALUES ('Sven', 'Olson', '1970-01-01', 'Single', 1, ${USA_ID}, '2000-01-01');
SQL

orangehrm_db_query "$(cat /tmp/seed_discrepancy_employees.sql)"

# 4. Verify creation
COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE emp_firstname IN ('Dario', 'Mei', 'Sven') AND emp_lastname IN ('Rossi', 'Chen', 'Olson') AND purged_at IS NULL;" 2>/dev/null | tr -d '[:space:]')
echo "Seeded $COUNT employees with incorrect data."

# 5. Ensure Browser is Logged In and at Dashboard
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# 6. Capture Initial State Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="