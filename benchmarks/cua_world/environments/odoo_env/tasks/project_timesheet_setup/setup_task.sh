#!/bin/bash
# Setup script for project_timesheet_setup task
# Ensures Project and Timesheet modules are installed and records initial state.

echo "=== Setting up project_timesheet_setup ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Install required modules and record initial state using Python
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Ensure 'project' and 'hr_timesheet' modules are installed
print("Checking for required modules...")
modules = execute('ir.module.module', 'search_read',
    [[['name', 'in', ['project', 'hr_timesheet']], ['state', '!=', 'installed']]],
    {'fields': ['id', 'name', 'state']})

if modules:
    print(f"Installing {len(modules)} modules: {[m['name'] for m in modules]}...")
    execute('ir.module.module', 'button_immediate_install', [[m['id'] for m in modules]])
    # Wait a bit for installation to settle (though immediate_install is blocking usually)
    time.sleep(5)
else:
    print("Required modules (project, hr_timesheet) are already installed.")

# 2. Record initial counts
initial_projects = execute('project.project', 'search_count', [[]])
initial_tasks = execute('project.task', 'search_count', [[]])
initial_timesheets = execute('account.analytic.line', 'search_count', [[]])

initial_state = {
    'project_count': initial_projects,
    'task_count': initial_tasks,
    'timesheet_count': initial_timesheets,
    'setup_timestamp': int(time.time())
}

with open('/tmp/project_timesheet_initial.json', 'w') as f:
    json.dump(initial_state, f)

print(f"Initial State Recorded: Projects={initial_projects}, Tasks={initial_tasks}, Timesheets={initial_timesheets}")
PYEOF

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="