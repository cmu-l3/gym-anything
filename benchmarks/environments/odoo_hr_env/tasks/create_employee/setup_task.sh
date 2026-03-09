#!/bin/bash
echo "=== Setting up create_employee task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing employee with the target name (clean slate)
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                 [[['name', '=', 'Sarah Mitchell']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'hr.employee', 'unlink', [existing])
        print(f"Removed existing employee 'Sarah Mitchell' (ids={existing})")
    else:
        print("No existing employee 'Sarah Mitchell' — clean slate")
    # Confirm Odoo demo employees are present
    emp_count = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search_count', [[]])
    print(f"Total employees: {emp_count} (Odoo official demo data)")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Employees kanban (Odoo official demo: 20 employees)
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Employees kanban (Odoo official demo: 20 employees)."
echo "Agent should create employee 'Sarah Mitchell' in R&D as Experienced Developer."
echo "=== create_employee task setup complete ==="
