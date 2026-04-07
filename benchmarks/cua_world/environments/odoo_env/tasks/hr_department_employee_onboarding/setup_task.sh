#!/bin/bash
echo "=== Setting up HR Onboarding Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done

# Ensure Employees (hr) module is installed
python3 << 'PYEOF'
import xmlrpc.client
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
    
    # Check if 'hr' module is installed
    modules = models.execute_kw(DB, uid, PASSWORD, 'ir.module.module', 'search_read', 
        [[['name', '=', 'hr'], ['state', '=', 'installed']]], 
        {'fields': ['name']})
        
    if not modules:
        print("Installing HR module...")
        # Find the module
        mod_id = models.execute_kw(DB, uid, PASSWORD, 'ir.module.module', 'search', [[['name', '=', 'hr']]])
        if mod_id:
            models.execute_kw(DB, uid, PASSWORD, 'ir.module.module', 'button_immediate_install', [mod_id])
            print("HR module installed.")
    else:
        print("HR module already installed.")

    # Record initial counts
    dept_count = models.execute_kw(DB, uid, PASSWORD, 'hr.department', 'search_count', [[]])
    emp_count = models.execute_kw(DB, uid, PASSWORD, 'hr.employee', 'search_count', [[]])
    
    with open('/tmp/initial_hr_counts.txt', 'w') as f:
        f.write(f"{dept_count},{emp_count}")

except Exception as e:
    print(f"Setup error: {e}")
PYEOF

# Ensure Firefox is open to the main menu
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' &"
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="