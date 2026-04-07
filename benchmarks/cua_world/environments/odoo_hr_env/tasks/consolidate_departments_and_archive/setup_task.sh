#!/bin/bash
set -e
echo "=== Setting up Consolidate Departments task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be responsive
echo "Waiting for Odoo..."
count=0
while ! curl -s "http://localhost:8069/web/health" | grep -q "200"; do
    if [ $count -ge 30 ]; then
        echo "Timeout waiting for Odoo"
        exit 1
    fi
    sleep 2
    count=$((count+1))
done

# Setup Data: Ensure 'R&D USA' exists and 'Robert Miller' is assigned to it
echo "Configuring Odoo data..."
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

    # 1. Ensure Target Department 'Research & Development' exists
    target_ids = models.execute_kw(db, uid, password, 'hr.department', 'search', [[['name', '=', 'Research & Development']]])
    if not target_ids:
        print("Error: Target department 'Research & Development' not found in demo data.")
        sys.exit(1)
    
    # 2. Find or Create Source Department 'R&D USA'
    # search both active and inactive
    source_ids = models.execute_kw(db, uid, password, 'hr.department', 'search', 
        [[['name', '=', 'R&D USA'], '|', ['active', '=', True], ['active', '=', False]]])
    
    if source_ids:
        source_id = source_ids[0]
        # Ensure it is active
        models.execute_kw(db, uid, password, 'hr.department', 'write', [[source_id], {'active': True}])
        print(f"Activated existing 'R&D USA' department (id={source_id})")
    else:
        source_id = models.execute_kw(db, uid, password, 'hr.department', 'create', [{'name': 'R&D USA'}])
        print(f"Created 'R&D USA' department (id={source_id})")

    # 3. Ensure Employee 'Robert Miller' exists and is in 'R&D USA'
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Robert Miller']]])
    if emp_ids:
        emp_id = emp_ids[0]
        models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'department_id': source_id}])
        print(f"Moved existing Robert Miller (id={emp_id}) to R&D USA")
    else:
        emp_id = models.execute_kw(db, uid, password, 'hr.employee', 'create', [{
            'name': 'Robert Miller',
            'department_id': source_id,
            'work_email': 'robert.miller@example.com',
            'job_title': 'Senior Researcher'
        }])
        print(f"Created Robert Miller (id={emp_id}) in R&D USA")

    # Record initial state
    with open('/tmp/initial_state.txt', 'w') as f:
        f.write(f"source_id={source_id}\n")
        f.write(f"emp_id={emp_id}\n")

except Exception as e:
    print(f"Error in setup script: {e}")
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Employees app
# We use the task_utils helper
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# Wait for window to settle
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="