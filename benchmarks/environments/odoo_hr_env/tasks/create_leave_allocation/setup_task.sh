#!/bin/bash
echo "=== Setting up create_leave_allocation task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing allocations for Randall Lewis
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Randall Lewis']]])
    if not emp_ids:
        print("ERROR: Employee 'Randall Lewis' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Remove all allocations for Randall Lewis that are in draft/confirm state
    alloc_ids = models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'search',
                                  [[['employee_id', '=', emp_id]]])
    if alloc_ids:
        # Try to reset to draft first, then delete
        for aid in alloc_ids:
            try:
                models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'action_draft', [[aid]])
            except Exception:
                pass
        models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'unlink', [alloc_ids])
        print(f"Removed {len(alloc_ids)} allocation(s) for Randall Lewis")
    else:
        print("No existing allocations for Randall Lewis — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to All Allocations view
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_allocation_action_all"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: All Allocations list (Odoo official demo data)."
echo "Agent should create and validate a 15-day Paid Time Off allocation for Randall Lewis."
echo "=== create_leave_allocation task setup complete ==="
