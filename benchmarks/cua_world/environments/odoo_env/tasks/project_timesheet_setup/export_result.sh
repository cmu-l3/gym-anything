#!/bin/bash
# Export script for project_timesheet_setup task

echo "=== Exporting project_timesheet_setup Result ==="

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER_DATE=$(date +%Y-%m-%d)

# Use Python to query Odoo state
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/project_timesheet_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Target Project Name
TARGET_NAME = "Westfield Manufacturing - ERP Implementation"

# 1. Find the project
projects = execute('project.project', 'search_read',
    [[['name', 'ilike', 'Westfield Manufacturing']]], # fuzzy match
    {'fields': ['id', 'name', 'allow_timesheets', 'create_date']})

project_found = False
project_data = {}
tasks_data = []
timesheets_data = []

if projects:
    # Get the most recent one matching the name
    p = projects[-1] # Assuming last created
    project_found = True
    project_data = p

    # 2. Get tasks for this project
    tasks = execute('project.task', 'search_read',
        [[['project_id', '=', p['id']]]],
        {'fields': ['id', 'name', 'date_deadline', 'create_date']})
    
    tasks_data = tasks

    # 3. Get timesheets (analytic lines) for these tasks
    task_ids = [t['id'] for t in tasks]
    if task_ids:
        lines = execute('account.analytic.line', 'search_read',
            [[['task_id', 'in', task_ids]]],
            {'fields': ['id', 'name', 'unit_amount', 'task_id', 'create_date']})
        timesheets_data = lines

# Load initial counts
try:
    with open('/tmp/project_timesheet_initial.json', 'r') as f:
        initial = json.load(f)
except:
    initial = {}

# Compile result
result = {
    'project_found': project_found,
    'project': project_data,
    'tasks': tasks_data,
    'timesheets': timesheets_data,
    'initial_counts': initial,
    'container_date': sys.argv[1] if len(sys.argv) > 1 else "",
    'export_timestamp': datetime.now().isoformat()
}

with open('/tmp/project_timesheet_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported: Project found={project_found}, Tasks={len(tasks_data)}, Timesheets={len(timesheets_data)}")
PYEOF "$CONTAINER_DATE"

# Clean up permissions
chmod 666 /tmp/project_timesheet_result.json 2>/dev/null || true

echo "=== Export Complete ==="