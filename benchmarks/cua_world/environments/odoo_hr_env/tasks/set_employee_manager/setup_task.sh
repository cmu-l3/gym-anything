#!/bin/bash
echo "=== Setting up set_employee_manager task ==="

source /workspace/scripts/task_utils.sh

# Reset Walter Horton's manager to Paul Williams (his demo data default); output dynamic ID
EMP_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Walter Horton']]])
    if not emp_ids:
        print("ERROR: Employee 'Walter Horton' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Find Paul Williams (Walter's original manager from demo data)
    mgr_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Paul Williams']]])
    mgr_id = mgr_ids[0] if mgr_ids else False

    models.execute_kw(db, uid, 'admin', 'hr.employee', 'write',
                      [[emp_id], {'parent_id': mgr_id}])
    mgr_name = 'Paul Williams' if mgr_id else 'none'
    print(f"Reset Walter Horton (id={emp_id}) manager to: {mgr_name}", file=sys.stderr)
    # Print only the ID to stdout for shell capture
    print(emp_id)
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

echo "Walter Horton employee ID: $EMP_ID"

# Navigate directly to Walter Horton's employee form using the dynamically resolved ID.
# The Manager field is visible on the main form card (no tab click required).
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my&id=${EMP_ID}&view_type=form"
sleep 4

take_screenshot /tmp/task_start.png

echo "Task start state: Walter Horton's employee form. Manager field shows 'Paul Williams'."
echo "Agent should set Marc Demo as Walter Horton's manager."
echo "=== set_employee_manager task setup complete ==="
