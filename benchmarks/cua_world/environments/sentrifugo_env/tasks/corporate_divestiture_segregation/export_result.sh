#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
sleep 1

# Run python script inside the container to reliably extract database state
cat > /tmp/export_db.py << 'EOF'
import subprocess
import json
import os

def query_db(query):
    cmd = ["docker", "exec", "sentrifugo-db", "mysql", "-u", "root", "-prootpass123", "sentrifugo", "-B", "-e", query]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        lines = res.strip().split('\n')
        if not lines or not lines[0]: return []
        headers = lines[0].split('\t')
        rows = []
        for line in lines[1:]:
            rows.append(dict(zip(headers, line.split('\t'))))
        return rows
    except Exception as e:
        return []

result = {}
# Get targeted users and a control user (EMP005)
result['users'] = query_db("SELECT * FROM main_users WHERE employeeId IN ('EMP008', 'EMP010', 'EMP012', 'EMP015', 'EMP018', 'EMP020', 'EMP005')")
result['summary'] = query_db("SELECT * FROM main_employees_summary WHERE user_id IN (SELECT id FROM main_users WHERE employeeId IN ('EMP008', 'EMP010', 'EMP012', 'EMP015', 'EMP018', 'EMP020', 'EMP005'))")

# Get job titles
result['jobtitles'] = query_db("SELECT * FROM main_jobtitles")

# Search for any table that might be employment status to be completely schema-agnostic
tables = query_db("SHOW TABLES")
status_tables = []
if tables:
    for t in tables:
        t_name = list(t.values())[0]
        if 'status' in t_name.lower():
            status_tables.append(t_name)

result['status_tables_data'] = {}
for st in status_tables:
    result['status_tables_data'][st] = query_db(f"SELECT * FROM {st}")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/export_db.py

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="