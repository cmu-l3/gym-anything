#!/bin/bash
set -e
echo "=== Setting up Create Onboarding Plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (UTC) for anti-gaming verification
date -u +%Y-%m-%d\ %H:%M:%S > /tmp/task_start_time_str.txt
date +%s > /tmp/task_start_time.txt

# -------------------------------------------------------
# Prepare Odoo State: Clean slate & verify dependencies
# -------------------------------------------------------
echo "Cleaning up any existing plans/activities..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Delete existing plan if it exists
    plan_ids = models.execute_kw(db, uid, password, 'mail.activity.plan', 'search',
                                 [[['name', '=', 'New Employee Onboarding']]])
    if plan_ids:
        print(f"Deleting existing plan IDs: {plan_ids}")
        # Note: Deleting plan cascades to templates usually
        models.execute_kw(db, uid, password, 'mail.activity.plan', 'unlink', [plan_ids])
    else:
        print("No existing plan found - clean slate.")

    # 2. Find Eli Lambert
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
                                [[['name', '=', 'Eli Lambert']]])
    if not emp_ids:
        print("ERROR: Employee 'Eli Lambert' not found!", file=sys.stderr)
        sys.exit(1)
    
    eli_id = emp_ids[0]
    
    # 3. Clear existing activities for Eli Lambert to ensure easy verification
    # We only clear 'mail.activity' records linked to this employee
    activity_ids = models.execute_kw(db, uid, password, 'mail.activity', 'search',
                                     [[['res_model', '=', 'hr.employee'], 
                                       ['res_id', '=', eli_id]]])
    if activity_ids:
        print(f"Clearing {len(activity_ids)} existing activities for Eli Lambert")
        models.execute_kw(db, uid, password, 'mail.activity', 'unlink', [activity_ids])

    # Record Eli's ID for verification
    with open('/tmp/target_employee_id.txt', 'w') as f:
        f.write(str(eli_id))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# -------------------------------------------------------
# Launch Application
# -------------------------------------------------------
# Navigate to HR Dashboard to start
ensure_firefox "http://localhost:8069/web#menu_id=184&action=255" # HR Dashboard (approximate ID, verified in generic env)
# Fallback to general web client if IDs vary
ensure_firefox "http://localhost:8069/web"

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="