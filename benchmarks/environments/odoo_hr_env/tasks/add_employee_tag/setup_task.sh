#!/bin/bash
echo "=== Setting up add_employee_tag task ==="

source /workspace/scripts/task_utils.sh

# Ensure Jennie Fletcher does NOT have the "Trainer" tag; output dynamic employee ID for URL
EMP_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Jennie Fletcher']]])
    if not emp_ids:
        print("ERROR: Employee 'Jennie Fletcher' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Find "Trainer" tag (from Odoo demo data)
    tag_ids = models.execute_kw(db, uid, 'admin', 'hr.employee.category', 'search',
                                [[['name', '=', 'Trainer']]])
    if not tag_ids:
        print("WARNING: Tag 'Trainer' not found in demo data", file=sys.stderr)
    else:
        tag_id = tag_ids[0]
        emp_data = models.execute_kw(db, uid, 'admin', 'hr.employee', 'read',
                                     [[emp_id]], {'fields': ['category_ids', 'name']})
        if emp_data:
            current_tags = emp_data[0].get('category_ids', [])
            if tag_id in current_tags:
                models.execute_kw(db, uid, 'admin', 'hr.employee', 'write',
                                  [[emp_id], {'category_ids': [(3, tag_id)]}])
                print(f"Removed 'Trainer' tag from Jennie Fletcher", file=sys.stderr)
            else:
                print(f"Jennie Fletcher does not have 'Trainer' tag — clean slate", file=sys.stderr)
            updated = models.execute_kw(db, uid, 'admin', 'hr.employee', 'read',
                                        [[emp_id]], {'fields': ['category_ids']})
            print(f"Jennie Fletcher current tags: {updated[0]['category_ids']}", file=sys.stderr)
    # Print only the ID to stdout for shell capture
    print(emp_id)
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

echo "Jennie Fletcher employee ID: $EMP_ID"

# Navigate directly to Jennie Fletcher's employee form using the dynamically resolved ID.
# The Tags field is shown in the main card area above the tabs.
# Pre-condition: "Employee" tag visible, "Trainer" tag absent — confirmed by the screenshot.
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my&id=${EMP_ID}&view_type=form"
sleep 4

take_screenshot /tmp/task_start.png

echo "Task start state: Jennie Fletcher's employee form — Tags shows 'Employee' only (no Trainer tag)."
echo "Agent should add the 'Trainer' tag to Jennie Fletcher via the HR Settings tab."
echo "=== add_employee_tag task setup complete ==="
