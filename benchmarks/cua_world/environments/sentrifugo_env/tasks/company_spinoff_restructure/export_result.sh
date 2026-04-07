#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Extracting database state to JSON..."
# We use Python inside bash to execute Docker commands, parse the output, 
# and safely structure it into a robust JSON for the verifier.
python3 << 'EOF'
import subprocess
import json
import os

def run_query(query):
    cmd = ["docker", "exec", "sentrifugo-db", "mysql", "-u", "root", "-prootpass123", "sentrifugo", "-N", "-e", query]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return [line.split('\t') for line in result.stdout.strip().split('\n') if line]
    except Exception as e:
        print(f"Query failed: {e}")
        return []

# 1. Get Employee States
# Query targets: Spinoff targets + Retained targets + Control target
users_query = """
SELECT u.employeeId, u.isactive, IFNULL(d.deptname, 'None')
FROM main_users u
LEFT JOIN main_departments d ON u.department_id = d.id
WHERE u.employeeId IN ('EMP005', 'EMP008', 'EMP014', 'EMP018', 'EMP011', 'EMP019', 'EMP003');
"""
users_data = run_query(users_query)
user_dict = {u[0]: {"isactive": int(u[1]), "dept": u[2]} for u in users_data if len(u) >= 3}

# 2. Get Department States
depts_query = """
SELECT deptname, isactive 
FROM main_departments
WHERE deptname IN ('Marketing', 'Sales', 'Vendor Management', 'Finance & Accounting');
"""
depts_data = run_query(depts_query)
dept_dict = {d[0]: {"isactive": int(d[1])} for d in depts_data if len(d) >= 2}

# Construct Final Export Payload
export_data = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "employees": user_dict,
    "departments": dept_dict,
    "screenshot_captured": os.path.exists("/tmp/task_final.png")
}

# Safely write to temp, then move (prevents permission locks)
with open("/tmp/temp_result.json", "w") as f:
    json.dump(export_data, f, indent=2)
EOF

mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="