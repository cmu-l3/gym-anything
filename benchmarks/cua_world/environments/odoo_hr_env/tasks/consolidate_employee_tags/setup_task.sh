#!/bin/bash
set -e
echo "=== Setting up Consolidate Employee Tags task ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data via Python/XML-RPC
# We need to ensure 'Consultant' tag exists and is assigned to specific employees.
# We need to ensure 'Contractor' tag does not exist (or is not assigned to them yet).

python3 << 'PYTHON_EOF'
import xmlrpc.client, sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Get or Create 'Consultant' tag
    tag_ids = models.execute_kw(db, uid, password, 'hr.employee.category', 'search', [[['name', '=', 'Consultant']]])
    if not tag_ids:
        consultant_id = models.execute_kw(db, uid, password, 'hr.employee.category', 'create', [{'name': 'Consultant'}])
        print(f"Created 'Consultant' tag: {consultant_id}")
    else:
        consultant_id = tag_ids[0]
        print(f"Found 'Consultant' tag: {consultant_id}")

    # 2. Ensure 'Contractor' tag does not exist (to force agent to create it or rename)
    # Actually, it's safer to just ensure it's not assigned to our targets. 
    # If we delete it, we might break other things, but usually 'Contractor' isn't in standard demo data.
    # Let's check if it exists.
    contractor_ids = models.execute_kw(db, uid, password, 'hr.employee.category', 'search', [[['name', '=', 'Contractor']]])
    if contractor_ids:
        # Just ensure it's not on our target employees
        pass

    # 3. Assign 'Consultant' to target employees
    targets = ['Jeffrey Kelly', 'Anita Oliver']
    target_ids = []
    
    for name in targets:
        emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', name]]])
        if emp_ids:
            emp_id = emp_ids[0]
            target_ids.append(emp_id)
            
            # Read current tags
            emp = models.execute_kw(db, uid, password, 'hr.employee', 'read', [emp_id], {'fields': ['category_ids']})[0]
            current_tags = emp['category_ids']
            
            # Add consultant_id if not present
            if consultant_id not in current_tags:
                # Odoo many2many write syntax: (4, id) adds link
                models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'category_ids': [(4, consultant_id)]}])
                print(f"Assigned 'Consultant' to {name}")
            
            # Remove contractor_ids if present
            if contractor_ids:
                for c_id in contractor_ids:
                    if c_id in current_tags:
                        models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'category_ids': [(3, c_id)]}])
                        print(f"Removed 'Contractor' from {name}")
        else:
            print(f"Warning: Employee {name} not found")

    # Save target IDs to file for verification later
    with open('/tmp/target_employee_ids.txt', 'w') as f:
        f.write(','.join(map(str, target_ids)))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Launch Firefox to Employees
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# 4. Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="