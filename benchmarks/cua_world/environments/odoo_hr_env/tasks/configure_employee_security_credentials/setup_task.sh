#!/bin/bash
set -e
echo "=== Setting up Configure Employee Security Credentials task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (Unix timestamp)
date +%s > /tmp/task_start_time.txt
# Also record formatted time for easier debugging/logging
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_iso.txt

# Reset credentials for the target employees to ensure a clean state
# This prevents previous runs from affecting verification and ensures "Do Nothing" fails
echo "Resetting target employee credentials..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    names = ['Anita Oliver', 'Toni Jimenez', 'Jeffrey Kelly']
    
    # Find employees
    domain = [['name', 'in', names]]
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [domain])
    
    if emp_ids:
        # Write empty values
        models.execute_kw(db, uid, password, 'hr.employee', 'write', [
            emp_ids, 
            {'barcode': False, 'pin': False}
        ])
        print(f"Reset credentials for {len(emp_ids)} employees.")
    else:
        print("Warning: Target employees not found during setup.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and navigated to the Employees list view
# This puts the agent in the correct starting context
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 5

# Maximize Firefox to ensure elements are visible
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="