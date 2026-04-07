#!/bin/bash
echo "=== Setting up configure_job_recruitment_settings task ==="

source /workspace/scripts/task_utils.sh

# 1. Identify the target Job Position ID and ensure it exists
# 2. Reset it to a clean state to ensure the task isn't already done
# 3. Store the ID for the export script to verify the SAME record is modified

python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, json
url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find "Marketing and Community Manager"
    job_ids = models.execute_kw(db, uid, password, 'hr.job', 'search',
                                [[['name', '=', 'Marketing and Community Manager']]])
    
    if not job_ids:
        # If not found (rare in demo data), create it
        job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{
            'name': 'Marketing and Community Manager',
            'no_of_recruitment': 1
        }])
        print(f"Created job position (id={job_id})")
    else:
        job_id = job_ids[0]
        print(f"Found existing job position (id={job_id})")

    # Reset values to ensure they are NOT the target values initially
    # Alias: marketing-manager, Recruiter: Mitchell Admin (uid=2 typically), Target: 1
    models.execute_kw(db, uid, password, 'hr.job', 'write', [[job_id], {
        'alias_name': 'marketing-manager-demo',
        'user_id': 2,  # Usually Mitchell Admin
        'no_of_recruitment': 1
    }])
    
    # Save ID for verification
    with open('/tmp/target_job_id.txt', 'w') as f:
        f.write(str(job_id))
        
    print(f"Reset job {job_id} to safe initial state.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox and navigate to the Job Positions list in Recruitment
# We use the action ID for "Job Positions" to help the agent start in the right place
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="