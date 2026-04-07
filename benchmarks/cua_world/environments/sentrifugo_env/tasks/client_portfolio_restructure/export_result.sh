#!/bin/bash
echo "=== Exporting client_portfolio_restructure task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png ga
sleep 1

# We will use Python to safely query the MySQL database inside the container
# and export the structured data to a JSON file.
cat > /tmp/extract_db_state.py << 'EOF'
import subprocess
import json
import sys

def run_query(sql):
    cmd = ['docker', 'exec', 'sentrifugo-db', 'mysql', '-u', 'root', '-prootpass123', 'sentrifugo', '-N', '-B', '-e', sql]
    try:
        return subprocess.check_output(cmd, text=True).strip()
    except Exception as e:
        return ""

result = {
    "projects": [],
    "tasks": [],
    "employees": []
}

# 1. Extract Projects (Looking for the legacy one and the two new ones)
sql_projects = """
SELECT p.projectname, p.isactive, c.clientname 
FROM main_projects p 
LEFT JOIN main_clients c ON p.client_id = c.id 
WHERE p.projectname IN ('General Plant Operations 2025', 'Biomass Grid Integration Phase 2', 'Facility Maintenance 2026');
"""
proj_raw = run_query(sql_projects)
if proj_raw:
    for line in proj_raw.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 3:
            result["projects"].append({
                "name": parts[0],
                "isactive": parts[1],
                "client": parts[2]
            })

# 2. Extract Tasks mapped to the new projects
sql_tasks = """
SELECT t.taskname, p.projectname 
FROM main_projecttasks t 
JOIN main_projects p ON t.project_id = p.id
WHERE p.projectname IN ('Biomass Grid Integration Phase 2', 'Facility Maintenance 2026')
AND t.isactive = 1;
"""
task_raw = run_query(sql_tasks)
if task_raw:
    for line in task_raw.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 2:
            result["tasks"].append({
                "taskname": parts[0],
                "projectname": parts[1]
            })

# 3. Extract Employees mapped to the projects
# Sentrifugo typically uses main_projectresources or main_projectallocations. 
# We'll check the most common tables dynamically.
mapping_tables = ['main_projectresources', 'main_projectallocations', 'main_projectemployees', 'main_projectmap']
for table in mapping_tables:
    sql_emps = f"""
    SELECT u.employeeId, p.projectname 
    FROM {table} t 
    JOIN main_users u ON t.user_id = u.id 
    JOIN main_projects p ON t.project_id = p.id
    WHERE p.projectname IN ('Biomass Grid Integration Phase 2', 'Facility Maintenance 2026');
    """
    emp_raw = run_query(sql_emps)
    if emp_raw and not emp_raw.startswith('ERROR'):
        for line in emp_raw.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 2:
                result["employees"].append({
                    "empid": parts[0],
                    "projectname": parts[1]
                })
        break # Successfully found and extracted from the right mapping table

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/extract_db_state.py

# Fix permissions so the framework can copy it out safely
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Extracted database state:"
cat /tmp/task_result.json
echo "=== Export complete ==="