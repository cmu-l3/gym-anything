#!/bin/bash
echo "=== Exporting employee_life_events_processing result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

log "Extracting DB state for verification..."

# We use a python script to cleanly extract database states into JSON
cat > /tmp/extract_db.py << 'EOF'
import subprocess
import json
import os

def query_db(query):
    cmd = [
        'docker', 'exec', 'sentrifugo-db', 'mysql', 
        '-u', 'root', '-prootpass123', 'sentrifugo', 
        '-N', '-B', '-e', query
    ]
    try:
        return subprocess.check_output(cmd, text=True).strip()
    except Exception:
        return ""

result = {}

# EMP005
uid_005 = query_db("SELECT id FROM main_users WHERE employeeId='EMP005'")
if uid_005:
    result['emp005_marital'] = query_db(f"SELECT maritalstatus FROM main_users WHERE id={uid_005}")
    result['emp005_marital_summary'] = query_db(f"SELECT marital_status FROM main_employees_summary WHERE user_id={uid_005}")
    result['emp005_address'] = query_db(f"SELECT presentaddress FROM main_employee_contactdetails WHERE user_id={uid_005}")
    result['emp005_contacts'] = query_db(f"SELECT name, relationship, homephone FROM main_employee_emergencycontacts WHERE user_id={uid_005}")

# EMP011
result['emp011_user'] = query_db("SELECT lastname, emailaddress, maritalstatus FROM main_users WHERE employeeId='EMP011'")
uid_011 = query_db("SELECT id FROM main_users WHERE employeeId='EMP011'")
if uid_011:
    result['emp011_marital_summary'] = query_db(f"SELECT marital_status FROM main_employees_summary WHERE user_id={uid_011}")

# EMP014
uid_014 = query_db("SELECT id FROM main_users WHERE employeeId='EMP014'")
if uid_014:
    result['emp014_contacts'] = query_db(f"SELECT name, relationship, homephone FROM main_employee_emergencycontacts WHERE user_id={uid_014}")

# EMP019
uid_019 = query_db("SELECT id FROM main_users WHERE employeeId='EMP019'")
if uid_019:
    result['emp019_contact'] = query_db(f"SELECT presentaddress, homephone, mobilephone FROM main_employee_contactdetails WHERE user_id={uid_019}")

# Application state
result['screenshot_exists'] = os.path.exists("/tmp/task_final.png")
result['task_start'] = ""
if os.path.exists("/tmp/task_start_time"):
    with open("/tmp/task_start_time", "r") as f:
        result['task_start'] = f.read().strip()

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/extract_db.py
chmod 666 /tmp/task_result.json

log "Database extraction complete."
cat /tmp/task_result.json
echo "=== Export complete ==="