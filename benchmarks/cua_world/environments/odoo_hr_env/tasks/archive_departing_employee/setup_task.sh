#!/bin/bash
set -e
echo "=== Setting up archive_departing_employee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running and accessible
# (Already handled by env setup, but good to be safe)
if ! curl -s "http://localhost:8069/web/health" > /dev/null; then
    echo "Waiting for Odoo to be ready..."
    sleep 5
fi

# ---------------------------------------------------------------------------
# Prepare Data: Ensure "Walter Horton" exists and is ACTIVE
# ---------------------------------------------------------------------------
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

    # Find Walter Horton (searching both active and inactive)
    # The domain ['|', ('active', '=', True), ('active', '=', False)] gets both
    ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
                            [[['name', '=', 'Walter Horton'], '|', ['active', '=', True], ['active', '=', False]]])
    
    if not ids:
        # If he doesn't exist (deleted in previous run), recreate him
        print("Walter Horton not found - recreating...")
        new_id = models.execute_kw(db, uid, password, 'hr.employee', 'create', [{
            'name': 'Walter Horton',
            'job_title': 'Sales Manager',
            'active': True
        }])
        print(f"Created Walter Horton (id={new_id})")
    else:
        # If he exists, ensure he is active
        emp_id = ids[0]
        data = models.execute_kw(db, uid, password, 'hr.employee', 'read', [[emp_id], ['active']])
        if not data[0]['active']:
            print(f"Walter Horton (id={emp_id}) is archived - reactivating...")
            models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'active': True}])
        else:
            print(f"Walter Horton (id={emp_id}) is already active.")

    # Record initial count of active employees for collateral damage check
    active_count = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', [[['active', '=', True]]])
    with open('/tmp/initial_active_count.txt', 'w') as f:
        f.write(str(active_count))
    print(f"Initial active employee count: {active_count}")

except Exception as e:
    print(f"Error in setup: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# ---------------------------------------------------------------------------
# Prepare Browser
# ---------------------------------------------------------------------------
# Navigate to Employees app (Kanban view)
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="