#!/bin/bash
set -e
echo "=== Setting up task: process_applicant_phone_screen ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Python setup script to prepare Odoo data
cat > /tmp/setup_applicant_data.py << 'PYTHON_EOF'
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

    # 1. Ensure Job Position 'Consultant' exists
    jobs = models.execute_kw(db, uid, password, 'hr.job', 'search_read',
                             [[['name', '=', 'Consultant']]], {'fields': ['id'], 'limit': 1})
    if not jobs:
        job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Consultant'}])
        print(f"Created Job 'Consultant' (ID: {job_id})")
    else:
        job_id = jobs[0]['id']
        print(f"Found Job 'Consultant' (ID: {job_id})")

    # 2. Ensure Stages 'New' and 'First Interview' exist
    # Note: Recruitment stages are often shared or specific to jobs. 
    # We will search for them by name.
    
    def get_stage_id(name):
        stages = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'search_read',
                                   [[['name', '=', name]]], {'fields': ['id'], 'limit': 1})
        if stages:
            return stages[0]['id']
        return None

    stage_new_id = get_stage_id('New')
    stage_interview_id = get_stage_id('First Interview')

    # If stages don't exist (unlikely in demo data), create them
    if not stage_new_id:
        stage_new_id = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'create', 
                                         [{'name': 'New', 'sequence': 1}])
    if not stage_interview_id:
        stage_interview_id = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'create', 
                                               [{'name': 'First Interview', 'sequence': 10}])

    # 3. Clean up any existing 'Alex Morgan' to ensure fresh state
    existing_applicants = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
                                            [[['partner_name', '=', 'Alex Morgan']]])
    if existing_applicants:
        models.execute_kw(db, uid, password, 'hr.applicant', 'unlink', [existing_applicants])
        print(f"Removed {len(existing_applicants)} existing applicant(s) named Alex Morgan")

    # 4. Create Applicant 'Alex Morgan' in 'New' stage
    app_id = models.execute_kw(db, uid, password, 'hr.applicant', 'create', [{
        'name': 'Consultant - Alex Morgan',
        'partner_name': 'Alex Morgan',
        'email_from': 'alex.morgan@example.com',
        'job_id': job_id,
        'stage_id': stage_new_id,
        'description': 'Applied via website. Resume looks good.',
        'probability': 0.0
    }])
    print(f"Created applicant Alex Morgan (ID: {app_id}) in stage 'New'")

except Exception as e:
    print(f"Error setting up data: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Execute the data setup
echo "Running Odoo data setup..."
python3 /tmp/setup_applicant_data.py

# Launch Firefox and navigate to the Recruitment Kanban view for 'Consultant'
# We need to find the action ID for recruitment to form the correct URL, 
# or just go to the recruitment dashboard.
# Safer to go to Recruitment dashboard: action=hr_recruitment.action_hr_job
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"

# Take initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="