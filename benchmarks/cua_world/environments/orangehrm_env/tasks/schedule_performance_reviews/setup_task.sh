#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up schedule_performance_reviews task ==="

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrangeHRM
wait_for_http "$ORANGEHRM_URL" 60

# 3. Create Data (Job Titles & Employees) via SQL
# We use a python script to handle the logic cleanly inside the setup
cat << 'EOF' > /tmp/setup_data.py
import subprocess
import sys

def run_sql(query):
    cmd = ["docker", "exec", "orangehrm-db", "mysql", "-u", "root", "-prootpass123", "orangehrm", "-N", "-e", query]
    return subprocess.check_output(cmd).decode('utf-8').strip()

def ensure_job_title(title):
    exists = run_sql(f"SELECT count(*) FROM ohrm_job_title WHERE job_title='{title}' AND is_deleted=0")
    if int(exists) == 0:
        print(f"Creating job title: {title}")
        run_sql(f"INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('{title}', 0)")
    return run_sql(f"SELECT id FROM ohrm_job_title WHERE job_title='{title}' LIMIT 1")

def ensure_employee(first, last, emp_id, job_title_id):
    # Check by emp_id first
    exists = run_sql(f"SELECT count(*) FROM hs_hr_employee WHERE employee_id='{emp_id}'")
    if int(exists) == 0:
        # Check by name
        exists_name = run_sql(f"SELECT count(*) FROM hs_hr_employee WHERE emp_firstname='{first}' AND emp_lastname='{last}'")
        if int(exists_name) == 0:
            print(f"Creating employee: {first} {last}")
            run_sql(f"INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id, job_title_code) VALUES ('{first}', '{last}', '{emp_id}', {job_title_id})")
        else:
            # Update existing to ensure job title matches
            run_sql(f"UPDATE hs_hr_employee SET job_title_code={job_title_id} WHERE emp_firstname='{first}' AND emp_lastname='{last}'")
    else:
        run_sql(f"UPDATE hs_hr_employee SET job_title_code={job_title_id} WHERE employee_id='{emp_id}'")

# Execute
mgr_title_id = ensure_job_title("Engineering Manager")
eng_title_id = ensure_job_title("Software Engineer")

ensure_employee("Elena", "Fisher", "MGR001", mgr_title_id)
ensure_employee("Michael", "Chen", "ENG001", eng_title_id)
ensure_employee("Sarah", "Jenkins", "ENG002", eng_title_id)

# Clear any existing reviews for these people to ensure clean state
print("Clearing existing reviews...")
ids_sql = "SELECT emp_number FROM hs_hr_employee WHERE employee_id IN ('MGR001', 'ENG001', 'ENG002')"
# We delete reviews where employee OR reviewer is one of our target people to avoid confusion
run_sql(f"DELETE FROM ohrm_performance_review WHERE employee_number IN ({ids_sql}) OR reviewer_number IN ({ids_sql})")

print("Data setup complete.")
EOF

python3 /tmp/setup_data.py

# 4. Login and Navigate
TARGET_URL="${ORANGEHRM_URL}/web/index.php/performance/searchPerformancReview"
ensure_orangehrm_logged_in "$TARGET_URL"

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="