#!/bin/bash
set -e
echo "=== Setting up update_employee_home_address task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset Audrey Peterson's address to a known initial state (to ensure task is performable)
# We use python/xmlrpc for this to interact with Odoo directly
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

    # Find Employee
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
        [[['name', '=', 'Audrey Peterson']]])
    
    if not emp_ids:
        print("Error: Employee Audrey Peterson not found")
        sys.exit(1)
        
    emp_id = emp_ids[0]
    
    # Get current address_home_id
    emp = models.execute_kw(db, uid, password, 'hr.employee', 'read',
        [emp_id], {'fields': ['address_home_id']})[0]
    
    address_id = emp['address_home_id'][0] if emp['address_home_id'] else None

    # If no address exists, create a dummy one. If exists, reset it.
    if address_id:
        models.execute_kw(db, uid, password, 'res.partner', 'write',
            [[address_id], {
                'street': '123 Old Road',
                'street2': False,
                'city': 'Old Town',
                'zip': '00000',
                'state_id': False
            }])
        print(f"Reset address for Audrey Peterson (Partner ID: {address_id})")
    else:
        # Create a new partner and link it
        new_addr_id = models.execute_kw(db, uid, password, 'res.partner', 'create',
            [{
                'name': 'Audrey Peterson (Private)',
                'type': 'private',
                'street': '123 Old Road',
                'city': 'Old Town',
                'zip': '00000'
            }])
        models.execute_kw(db, uid, password, 'hr.employee', 'write',
            [[emp_id], {'address_home_id': new_addr_id}])
        print(f"Created and linked new dummy address for Audrey Peterson (Partner ID: {new_addr_id})")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and on the Employees list
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="