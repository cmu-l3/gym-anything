#!/bin/bash
echo "=== Setting up Transfer Applicant Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Python script to setup the initial state of the applicant
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure required Job Positions and Departments exist (Demo data usually has them)
    # Target: Consultant
    consultant_job = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Consultant']]])
    if not consultant_job:
        # Create if missing (fallback)
        print("Creating missing Consultant job...")
        prof_serv_dept = models.execute_kw(db, uid, password, 'hr.department', 'search', [[['name', '=', 'Professional Services']]])
        dept_id = prof_serv_dept[0] if prof_serv_dept else models.execute_kw(db, uid, password, 'hr.department', 'create', [{'name': 'Professional Services'}])
        consultant_job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Consultant', 'department_id': dept_id}])
    else:
        consultant_job_id = consultant_job[0]

    # Source: Marketing
    marketing_job = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Marketing and Community Manager']]])
    if not marketing_job:
        print("Creating missing Marketing job...")
        sales_dept = models.execute_kw(db, uid, password, 'hr.department', 'search', [[['name', '=', 'Sales']]])
        dept_id = sales_dept[0] if sales_dept else models.execute_kw(db, uid, password, 'hr.department', 'create', [{'name': 'Sales'}])
        marketing_job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Marketing and Community Manager', 'department_id': dept_id}])
    else:
        marketing_job_id = marketing_job[0]

    # 2. Setup Applicant "Alex Morgan"
    applicant_name = "Alex Morgan"
    # Search for existing
    applicants = models.execute_kw(db, uid, password, 'hr.applicant', 'search', [[['partner_name', '=', applicant_name]]])
    
    if applicants:
        # Reset existing applicant
        app_id = applicants[0]
        print(f"Resetting existing applicant {applicant_name} (ID: {app_id})")
        
        # Remove "Reassigned" tag if present
        tag_ids = models.execute_kw(db, uid, password, 'hr.applicant.category', 'search', [[['name', '=', 'Reassigned']]])
        if tag_ids:
             # Odoo write to many2many: (3, id) removes association
             models.execute_kw(db, uid, password, 'hr.applicant', 'write', [[app_id], {'category_ids': [[3, tag_ids[0]]] }])

        # Set back to Marketing job
        # We also need to fetch the department for the marketing job to set it correctly
        marketing_data = models.execute_kw(db, uid, password, 'hr.job', 'read', [marketing_job_id], {'fields': ['department_id']})
        marketing_dept_id = marketing_data[0]['department_id'][0] if marketing_data[0]['department_id'] else False

        models.execute_kw(db, uid, password, 'hr.applicant', 'write', [[app_id], {
            'job_id': marketing_job_id,
            'department_id': marketing_dept_id,
            'name': 'Marketing Application', # Subject
            'stage_id': 1, # Usually 'New' or 'Initial Qualification'
        }])
    else:
        # Create new applicant
        print(f"Creating new applicant {applicant_name}")
        marketing_data = models.execute_kw(db, uid, password, 'hr.job', 'read', [marketing_job_id], {'fields': ['department_id']})
        marketing_dept_id = marketing_data[0]['department_id'][0] if marketing_data[0]['department_id'] else False
        
        models.execute_kw(db, uid, password, 'hr.applicant', 'create', [{
            'partner_name': applicant_name,
            'name': 'Marketing Application',
            'job_id': marketing_job_id,
            'department_id': marketing_dept_id,
            'email_from': 'alex.morgan@example.com',
            'description': 'Experienced in marketing strategies and community engagement.',
        }])

    print("Applicant setup complete.")

except Exception as e:
    print(f"Error during setup: {e}")
    sys.exit(1)
PYTHON_EOF

# Launch Firefox to the Recruitment Kanban view
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job_sources"
sleep 5

# Navigate specifically to the Marketing job applications if possible, or just the main dashboard
# The dashboard is usually the entry point.
# Let's try to go to the specific applicant view if we can, but the dashboard is more realistic starting point.
# URL for Recruitment Dashboard:
navigate_firefox "http://localhost:8069/web#menu_id=hr_recruitment.menu_hr_recruitment_root"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="