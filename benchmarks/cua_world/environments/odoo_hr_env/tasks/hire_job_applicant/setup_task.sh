#!/bin/bash
set -e
echo "=== Setting up Hire Job Applicant task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Python script to prepare specific data via XML-RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Error: Authentication failed", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Clean up: Remove any existing employee or applicant named "Sofia Martinez"
    # to ensure a clean start state.
    
    # Remove Employee
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
                                [[['name', '=', 'Sofia Martinez']]])
    if emp_ids:
        models.execute_kw(db, uid, password, 'hr.employee', 'unlink', [emp_ids])
        print(f"Cleaned up {len(emp_ids)} existing employee(s)")

    # Remove Applicant
    app_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
                                [[['partner_name', '=', 'Sofia Martinez']]])
    if app_ids:
        models.execute_kw(db, uid, password, 'hr.applicant', 'unlink', [app_ids])
        print(f"Cleaned up {len(app_ids)} existing applicant(s)")

    # 2. Get dependencies (Job Position, Department, Stages)
    
    # Job: Experienced Developer
    job_ids = models.execute_kw(db, uid, password, 'hr.job', 'search',
                                [[['name', '=', 'Experienced Developer']]])
    if not job_ids:
        # Create if missing (though demo data usually has it)
        job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', 
                                   [{'name': 'Experienced Developer'}])
        print("Created missing job position")
    else:
        job_id = job_ids[0]

    # Stage: "New" (Initial stage)
    # We find the stage with lowest sequence for this job or global
    stage_ids = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'search',
                                  [[]], {'order': 'sequence asc', 'limit': 1})
    stage_id = stage_ids[0] if stage_ids else False

    # 3. Create the Applicant "Sofia Martinez"
    new_applicant_id = models.execute_kw(db, uid, password, 'hr.applicant', 'create', [{
        'partner_name': 'Sofia Martinez',
        'name': 'Experienced Developer - Sofia Martinez', # Subject
        'job_id': job_id,
        'stage_id': stage_id,
        'email_from': 'sofia.martinez@example.com',
        'partner_phone': '555-0199',
        'description': 'Senior Python developer with Odoo experience.',
    }])
    print(f"Created applicant 'Sofia Martinez' (ID: {new_applicant_id})")

    # Record initial employee count for verification
    initial_count = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', [[]])
    with open('/tmp/initial_employee_count.txt', 'w') as f:
        f.write(str(initial_count))
    print(f"Initial employee count: {initial_count}")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Recruitment Kanban view
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job_applications&model=hr.applicant&view_type=kanban"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="