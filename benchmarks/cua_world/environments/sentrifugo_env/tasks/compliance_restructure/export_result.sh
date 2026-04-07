#!/bin/bash
echo "=== Exporting compliance_restructure result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Use a Python script to query the database and safely output structured JSON.
# This avoids bash string parsing nightmares.
python3 << 'EOF'
import json
import subprocess
import os

def db_query(q):
    cmd = [
        "docker", "exec", "sentrifugo-db", "mysql", 
        "-u", "sentrifugo", "-psentrifugo123", "sentrifugo", 
        "-N", "-B", "-e", q
    ]
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception as e:
        return ""

data = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "departments": {},
    "job_titles": {},
    "employees": {},
    "maint_support_active_count": 0
}

# 1. Get Departments state
dept_raw = db_query("SELECT deptname, deptcode, isactive FROM main_departments;")
for line in dept_raw.split('\n'):
    if '\t' in line:
        parts = line.split('\t')
        if len(parts) >= 3:
            data["departments"][parts[0]] = {"code": parts[1], "isactive": parts[2]}

# 2. Get Job Titles state
jt_raw = db_query("SELECT jobtitlename, jobtitlecode FROM main_jobtitles WHERE jobtitlename IN ('Systems Engineer', 'Network Administrator', 'Marketing Specialist');")
for line in jt_raw.split('\n'):
    if '\t' in line:
        parts = line.split('\t')
        if len(parts) >= 2:
            data["job_titles"][parts[0]] = parts[1]

# 3. Get Employee Assignments
emp_raw = db_query("SELECT u.employeeId, d.deptname FROM main_users u JOIN main_employees_summary es ON u.id=es.user_id JOIN main_departments d ON es.department_id=d.id WHERE u.employeeId IN ('EMP009', 'EMP010', 'EMP014', 'EMP017');")
for line in emp_raw.split('\n'):
    if '\t' in line:
        parts = line.split('\t')
        if len(parts) >= 2:
            data["employees"][parts[0]] = parts[1]

# 4. Check active employees in Maintenance & Support
ms_count = db_query("SELECT COUNT(*) FROM main_users u JOIN main_employees_summary es ON u.id=es.user_id JOIN main_departments d ON es.department_id=d.id WHERE d.deptname='Maintenance & Support' AND u.isactive=1;")
try:
    data["maint_support_active_count"] = int(ms_count) if ms_count else 0
except:
    pass

with open('/tmp/compliance_restructure_result.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

# Ensure file permissions are accessible to the verifier
chmod 666 /tmp/compliance_restructure_result.json 2>/dev/null || sudo chmod 666 /tmp/compliance_restructure_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/compliance_restructure_result.json"
cat /tmp/compliance_restructure_result.json
echo "=== Export complete ==="