#!/bin/bash
echo "=== Setting up update_employee_job_title task ==="

source /workspace/scripts/task_utils.sh

# Ensure Marc Demo's Job Title is cleared; output dynamic employee ID for URL
EMP_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Marc Demo']]])
    if not emp_ids:
        print("ERROR: Employee 'Marc Demo' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Clear the job_title field (free-text field, separate from job_id/Job Position dropdown)
    models.execute_kw(db, uid, 'admin', 'hr.employee', 'write',
                      [[emp_id], {'job_title': ''}])
    emp_data = models.execute_kw(db, uid, 'admin', 'hr.employee', 'read',
                                 [[emp_id]], {'fields': ['name', 'job_id', 'job_title']})
    if emp_data:
        d = emp_data[0]
        job_name = d['job_id'][1] if d['job_id'] else 'none'
        print(f"Marc Demo (id={emp_id}): Job Position='{job_name}', Job Title='' (cleared)", file=sys.stderr)
    # Print only the ID to stdout for shell capture
    print(emp_id)
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

echo "Marc Demo employee ID: $EMP_ID"

# Navigate directly to Marc Demo's employee form using the dynamically resolved ID
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my&id=${EMP_ID}&view_type=form"
sleep 4

take_screenshot /tmp/task_start.png

echo "Task start state: Marc Demo's employee form with Job Title field empty."
echo "Agent should update Marc Demo's Job Title to 'Lead Developer'."
echo "=== update_employee_job_title task setup complete ==="
