#!/bin/bash
echo "=== Exporting grant_project_timesheet_setup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Create a python script to safely query and export the database state
# This script uses dynamic table discovery to guarantee resource allocations are found
cat > /tmp/export_db.py << 'PYEOF'
import json
import subprocess

def query_db(query):
    cmd = f'docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "{query}"'
    try:
        res = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return [line.split('\t') for line in res.split('\n') if line]
    except Exception as e:
        return []

clients = []
try:
    for r in query_db("SELECT id, clientname FROM main_clients WHERE isactive=1"):
        if len(r) >= 2:
            clients.append({'id': r[0], 'name': r[1]})
except:
    pass

projects = []
try:
    for r in query_db("SELECT id, projectname, client_id FROM main_projects WHERE isactive=1"):
        if len(r) >= 3:
            projects.append({'id': r[0], 'name': r[1], 'client_id': r[2]})
except:
    pass

# Discover resource table dynamically
tables = [r[0] for r in query_db("SHOW TABLES")]
resources = []
for t in tables:
    if ('project' in t.lower()) and ('resource' in t.lower() or 'allocation' in t.lower() or 'member' in t.lower() or 'user' in t.lower() or 'employee' in t.lower()):
        cols = [r[0] for r in query_db(f"SHOW COLUMNS FROM {t}")]
        proj_col = 'project_id' if 'project_id' in cols else 'projectid' if 'projectid' in cols else 'project' if 'project' in cols else None
        user_col = 'user_id' if 'user_id' in cols else 'userid' if 'userid' in cols else 'employee_id' if 'employee_id' in cols else None
        
        if proj_col and user_col:
            allocs_query = f"SELECT {proj_col}, {user_col} FROM {t} WHERE isactive=1" if 'isactive' in cols else f"SELECT {proj_col}, {user_col} FROM {t}"
            allocs = query_db(allocs_query)
            for a in allocs:
                if len(a) >= 2:
                    empid_rows = query_db(f"SELECT employeeId FROM main_users WHERE id={a[1]}")
                    if empid_rows and len(empid_rows[0]) > 0:
                        resources.append({'project_id': a[0], 'empid': empid_rows[0][0], 'table': t})

result = {
    'clients': clients,
    'projects': projects,
    'resources': resources,
    'screenshot_exists': True
}

with open('/tmp/grant_task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/export_db.py

# Ensure permissions allow the framework to copy the file
chmod 666 /tmp/grant_task_result.json 2>/dev/null || sudo chmod 666 /tmp/grant_task_result.json 2>/dev/null || true

echo "Export completed. Results summary:"
cat /tmp/grant_task_result.json