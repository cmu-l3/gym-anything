#!/bin/bash
set -e
echo "=== Setting up archive_withdrawn_applications task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Use Python/XML-RPC to setup the data state
# 1. Ensure Trainee job exists
# 2. Clean any existing James Miller records
# 3. Create 3 new active applications for James Miller
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
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure "Trainee" job position exists
    jobs = models.execute_kw(db, uid, password, 'hr.job', 'search_read',
                             [[['name', '=', 'Trainee']]],
                             {'fields': ['id'], 'limit': 1})
    if not jobs:
        job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Trainee'}])
        print(f"Created 'Trainee' job position (id={job_id})")
    else:
        job_id = jobs[0]['id']

    # 2. Clean up ANY existing applications for James Miller (active OR archived)
    # We search with active_test=False context to find archived ones too if we could, 
    # but via API we use '|' operator for active field
    existing_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
        [['|', ['active', '=', True], ['active', '=', False], 
          ['partner_name', '=', 'James Miller']]])
    
    if existing_ids:
        models.execute_kw(db, uid, password, 'hr.applicant', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing records for James Miller")

    # 3. Create 3 Active applications
    created_ids = []
    for i in range(1, 4):
        app_id = models.execute_kw(db, uid, password, 'hr.applicant', 'create', [{
            'name': f'Trainee Application - James Miller {i}',
            'partner_name': 'James Miller',
            'email_from': 'james.miller@example.com',
            'job_id': job_id,
            'stage_id': 1,  # Usually 'New' or 'Initial Qualification'
            'description': 'Withdrawing soon.',
            'active': True
        }])
        created_ids.append(app_id)

    print(f"Created 3 active applications for James Miller: {created_ids}")
    
    # Verify creation
    count = models.execute_kw(db, uid, password, 'hr.applicant', 'search_count',
                              [[['partner_name', '=', 'James Miller'], ['active', '=', True]]])
    print(f"Verification: {count} active applications found.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox directly to the Recruitment Kanban view for Trainee
# This puts the agent right in front of the data
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#model=hr.job&view_type=kanban"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="