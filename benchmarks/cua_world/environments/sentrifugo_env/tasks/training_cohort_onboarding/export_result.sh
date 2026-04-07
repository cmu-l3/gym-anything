#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record end time and take final screenshot
date +%s > /tmp/task_end_timestamp
take_screenshot /tmp/task_final.png ga

# Create a Python script to reliably extract the database state into JSON
# This avoids bash parsing issues with MySQL TSV outputs
cat > /tmp/export_db.py << 'PYEOF'
import subprocess
import json

def query(sql):
    cmd = f'docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "{sql}"'
    try:
        res = subprocess.check_output(cmd, shell=True, text=True)
        lines = res.strip().split('\n')
        if not lines or not lines[0]: return []
        headers = lines[0].split('\t')
        rows = []
        for line in lines[1:]:
            rows.append(dict(zip(headers, line.split('\t'))))
        return rows
    except Exception as e:
        print(f"Error executing query: {e}")
        return []

print("Extracting Sentrifugo database state...")

# Extract relevant tables
users = query("SELECT * FROM main_users WHERE employeeId IN ('EMP021', 'EMP022', 'EMP023') OR firstname IN ('Amara', 'Rajesh', 'Sofia')")
user_ids = [u['id'] for u in users] if users else []
uid_str = ','.join(user_ids) if user_ids else '0'

managers_pool = query("SELECT id, employeeId, firstname, lastname FROM main_users WHERE employeeId IN ('EMP001', 'EMP005', 'EMP010')")

result = {
    'job_titles': query("SELECT * FROM main_jobtitles WHERE jobtitlename='Training Coordinator'"),
    'users': users,
    'employees': query(f"SELECT * FROM main_employees WHERE user_id IN ({uid_str})"),
    'summary': query(f"SELECT * FROM main_employees_summary WHERE user_id IN ({uid_str})"),
    'managers': query(f"SELECT * FROM main_managers WHERE user_id IN ({uid_str})"),
    'departments_lookup': query("SELECT id, deptname FROM main_departments"),
    'jobtitles_lookup': query("SELECT id, jobtitlename FROM main_jobtitles"),
    'manager_lookup': managers_pool
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export saved to /tmp/task_result.json")
PYEOF

python3 /tmp/export_db.py

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="