#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_leave_type task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing "Work From Home" leave type to ensure a fresh start
echo "Cleaning up existing data..."
python3 << 'EOF'
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
    
    # Find existing types
    existing_ids = models.execute_kw(db, uid, password, 'hr.leave.type', 'search',
        [[['name', 'ilike', 'Work From Home']]])
    
    if existing_ids:
        print(f"Found {len(existing_ids)} existing 'Work From Home' types. Archiving/Deleting...")
        # Archive first (Odoo best practice as direct unlink might be restricted if used)
        models.execute_kw(db, uid, password, 'hr.leave.type', 'write',
            [existing_ids, {'active': False}])
        # Try to unlink (delete)
        try:
            models.execute_kw(db, uid, password, 'hr.leave.type', 'unlink', [existing_ids])
            print("Successfully deleted existing types.")
        except Exception as e:
            print(f"Could not delete (likely linked to records), but archived: {e}")
    else:
        print("No existing 'Work From Home' types found.")

    # Record initial count of active leave types
    count = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_count', [[['active', '=', True]]])
    with open('/tmp/initial_count.txt', 'w') as f:
        f.write(str(count))
        
except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF

# 2. Launch Firefox and navigate to Odoo Time Off Dashboard
# This puts the agent in the right app but requires them to find "Configuration"
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr_holidays.action_hr_holidays_dashboard"

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="