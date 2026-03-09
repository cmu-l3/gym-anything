#!/bin/bash
echo "=== Setting up create_department task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing "Product Management" department to ensure fresh start
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'hr.department', 'search',
                                 [[['name', '=', 'Product Management']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'hr.department', 'unlink', [existing])
        print(f"Removed existing department 'Product Management' (ids={existing})")
    else:
        print("No existing 'Product Management' department — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Departments list in Employees app
ensure_firefox "http://localhost:8069/web#action=hr.hr_department_tree_action"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Departments list. No 'Product Management' department exists."
echo "Agent should create 'Product Management' department with Tina Williamson as Manager."
echo "=== create_department task setup complete ==="
