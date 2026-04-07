#!/bin/bash
set -e
echo "=== Setting up hire_candidate_setup_email task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrangeHRM to be ready
wait_for_http "$ORANGEHRM_URL" 60

echo "Preparing database state..."

# SQL to seed the specific candidate state
# 1. Clean up any previous runs (Employee and Candidate)
# 2. Ensure Vacancy exists
# 3. Insert Candidate in 'Job Offered' status

cat > /tmp/seed_hire_task.sql << SQLEOF
-- Cleanup existing data to ensure fresh start
DELETE FROM hs_hr_employee WHERE emp_firstname='Elias' AND emp_lastname='Thorne';
DELETE FROM ohrm_job_candidate WHERE first_name='Elias' AND last_name='Thorne';

-- Ensure Job Title 'Sales Representative' exists
INSERT IGNORE INTO ohrm_job_title (job_title, is_deleted) VALUES ('Sales Representative', 0);
SET @job_title_id = (SELECT id FROM ohrm_job_title WHERE job_title='Sales Representative' LIMIT 1);

-- Ensure Hiring Manager (admin) exists
SET @manager_id = (SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Admin' LIMIT 1);
-- If Admin employee record missing (rare), fallback to emp_number 1
SET @manager_id = IFNULL(@manager_id, 1);

-- Ensure Vacancy 'Sales Representative' exists and is Active
INSERT IGNORE INTO ohrm_job_vacancy (name, job_title_code, hiring_manager_id, status, defined_time)
VALUES ('Sales Representative', @job_title_id, @manager_id, 1, NOW());
SET @vacancy_id = (SELECT id FROM ohrm_job_vacancy WHERE name='Sales Representative' LIMIT 1);

-- Insert Candidate 'Elias Thorne'
-- We need the 'Job Offered' status ID. In standard OrangeHRM 5.x:
-- Statuses are often configurable, but usually 'Job Offered' is a standard workflow step.
-- We will try to find it, or fallback to a hardcoded ID (often 6 or similar).
SET @status_id = (SELECT id FROM ohrm_job_candidate_status WHERE status_label LIKE '%Offered%' LIMIT 1);
-- Fallback if not found (standard seed often has ids 1-9)
SET @status_id = IFNULL(@status_id, 6); 

INSERT INTO ohrm_job_candidate (first_name, last_name, email, contact_number, status, vacancy_id, date_of_application, mode_of_application)
VALUES ('Elias', 'Thorne', 'elias.temp@example.com', '555-0199', @status_id, @vacancy_id, DATE_SUB(NOW(), INTERVAL 5 DAY), 1);

SET @candidate_id = LAST_INSERT_ID();

-- Add history entry to make it look legitimate in UI
INSERT INTO ohrm_job_candidate_history (candidate_id, vacancy_id, performed_date, status, action, performed_by)
VALUES (@candidate_id, @vacancy_id, NOW(), @status_id, 1, 1);

SQLEOF

# Execute SQL
orangehrm_db_query "$(cat /tmp/seed_hire_task.sql)"

# Verify seed success
CANDIDATE_CHECK=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_candidate WHERE first_name='Elias' AND last_name='Thorne'" | tr -d '[:space:]')
if [ "$CANDIDATE_CHECK" -eq "0" ]; then
    echo "ERROR: Failed to seed candidate Elias Thorne."
    exit 1
fi
echo "Candidate seeded successfully."

# Login and navigate to Recruitment module
TARGET_URL="${ORANGEHRM_URL}/web/index.php/recruitment/viewCandidates"
ensure_orangehrm_logged_in "$TARGET_URL"

# Initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured."

echo "=== Task setup complete ==="