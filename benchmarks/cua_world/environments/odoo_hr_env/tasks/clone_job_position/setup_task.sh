#!/bin/bash
set -e
echo "=== Setting up clone_job_position task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use Python to prepare data state via XML-RPC
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

    # 1. Ensure Source Job 'Experienced Developer' exists
    source_job = models.execute_kw(db, uid, password, 'hr.job', 'search',
                                   [[['name', '=', 'Experienced Developer']]])
    if not source_job:
        # Create it if missing (unlikely in demo data, but safe to ensure)
        print("Creating missing source job 'Experienced Developer'")
        models.execute_kw(db, uid, password, 'hr.job', 'create', [{
            'name': 'Experienced Developer',
            'no_of_recruitment': 1,
            'description': '<p>Standard developer role description.</p>'
        }])
    else:
        print("Source job 'Experienced Developer' exists.")

    # 2. Ensure Target Job 'Senior Python Developer' does NOT exist (Clean Slate)
    target_job = models.execute_kw(db, uid, password, 'hr.job', 'search',
                                   [[['name', '=', 'Senior Python Developer']]])
    if target_job:
        print(f"Removing pre-existing target job 'Senior Python Developer' (id={target_job})")
        models.execute_kw(db, uid, password, 'hr.job', 'unlink', [target_job])
    
    # 3. Ensure Department 'R&D USA' exists
    dept = models.execute_kw(db, uid, password, 'hr.department', 'search',
                             [[['name', '=', 'R&D USA']]])
    if not dept:
        print("Creating missing department 'R&D USA'")
        models.execute_kw(db, uid, password, 'hr.department', 'create', [{
            'name': 'R&D USA'
        }])

    # Record initial job count
    count = models.execute_kw(db, uid, password, 'hr.job', 'search_count', [[]])
    with open('/tmp/initial_job_count.txt', 'w') as f:
        f.write(str(count))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox to the Recruitment/Job Positions Kanban view
# This puts the agent in the right app to find the job and duplicate it
echo "Launching Firefox to Job Positions..."
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="