#!/bin/bash
echo "=== Exporting schedule_performance_reviews result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Data from DB to JSON using Python
# We map the SQL results to a structured JSON for the verifier
cat << 'EOF' > /tmp/export_data.py
import subprocess
import json
import sys

def run_sql(query):
    # -N for no headers
    cmd = ["docker", "exec", "orangehrm-db", "mysql", "-u", "root", "-prootpass123", "orangehrm", "-N", "-e", query]
    try:
        return subprocess.check_output(cmd).decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return ""

def get_reviews():
    # Fetch review details: review_id, Employee Name, Reviewer Name, Status, Start, End, Due
    # Status ID 1 = Inactive, 2 = Activated/In Progress (usually)
    query = """
    SELECT 
        r.id,
        CONCAT(e.emp_firstname, ' ', e.emp_lastname) as employee,
        CONCAT(rev.emp_firstname, ' ', rev.emp_lastname) as reviewer,
        r.status_id,
        r.work_period_start,
        r.work_period_end,
        r.due_date
    FROM ohrm_performance_review r
    JOIN hs_hr_employee e ON r.employee_number = e.emp_number
    JOIN hs_hr_employee rev ON r.reviewer_number = rev.emp_number
    WHERE e.emp_firstname IN ('Michael', 'Sarah') 
      AND e.emp_lastname IN ('Chen', 'Jenkins')
    ORDER BY r.id DESC;
    """
    
    output = run_sql(query)
    reviews = []
    if output:
        for line in output.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 7:
                reviews.append({
                    "id": parts[0],
                    "employee": parts[1],
                    "reviewer": parts[2],
                    "status_id": int(parts[3]),
                    "start_date": parts[4],
                    "end_date": parts[5],
                    "due_date": parts[6]
                })
    return reviews

data = {
    "reviews": get_reviews(),
    "screenshot_path": "/tmp/task_final.png"
}

print(json.dumps(data, indent=2))
EOF

# Run export script and save to /tmp/task_result.json
python3 /tmp/export_data.py > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="