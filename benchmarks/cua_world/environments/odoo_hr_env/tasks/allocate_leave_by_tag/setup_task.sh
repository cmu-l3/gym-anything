#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up allocate_leave_by_tag task ==="

# Record task start time for anti-gaming (records created before this don't count)
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running
if ! pgrep -f "odoo" > /dev/null; then
    echo "Starting Odoo..."
    # Assumes container environment where Odoo is managed by supervisor/docker
    # If not, we'd start it here. In this env, it's usually pre-started.
fi

# ---------------------------------------------------------------------------
# Python Setup Script
# 1. Ensures 'Consultant' tag exists
# 2. Ensures 'Paid Time Off' exists
# 3. Tags 'Marc Demo' as a Consultant so the action has a real effect
# ---------------------------------------------------------------------------
python3 << PYTHON_EOF
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure 'Consultant' tag exists
    tag_ids = models.execute_kw(db, uid, password, 'hr.employee.category', 'search', [[['name', '=', 'Consultant']]])
    if not tag_ids:
        tag_id = models.execute_kw(db, uid, password, 'hr.employee.category', 'create', [{'name': 'Consultant'}])
        print(f"Created Consultant tag: {tag_id}")
    else:
        tag_id = tag_ids[0]
        print(f"Found Consultant tag: {tag_id}")

    # 2. Ensure 'Paid Time Off' type exists
    pto_ids = models.execute_kw(db, uid, password, 'hr.leave.type', 'search', [[['name', '=', 'Paid Time Off']]])
    if not pto_ids:
        # Fallback: Create it if missing (unlikely in standard demo data)
        print("Warning: 'Paid Time Off' type not found. Task might be harder than expected.", file=sys.stderr)
    else:
        print(f"Found Paid Time Off type: {pto_ids[0]}")

    # 3. Ensure 'Marc Demo' has the Consultant tag
    # This ensures that when the agent selects "Consultant", it actually applies to someone.
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Marc Demo']]])
    if emp_ids:
        emp = models.execute_kw(db, uid, password, 'hr.employee', 'read', [emp_ids[0]], {'fields': ['category_ids']})
        current_tags = emp[0]['category_ids']
        if tag_id not in current_tags:
            models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_ids[0]], {'category_ids': [[4, tag_id]]}])
            print("Added Consultant tag to Marc Demo")
        else:
            print("Marc Demo already has Consultant tag")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox directly to Allocations menu to save time
# Action ID for "Allocations" usually exists in hr_holidays
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_allocation_action_all"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="