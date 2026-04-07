#!/bin/bash
echo "=== Setting up create_job_application task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial state and clean up any previous attempts
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Clean up any existing "Maria Chen" applicants
    existing = models.execute_kw(db, uid, 'admin', 'hr.applicant', 'search',
                                [[['partner_name', 'ilike', 'Maria Chen']]])
    if existing:
        print(f"Cleaning up {len(existing)} existing applicant(s) for Maria Chen...")
        models.execute_kw(db, uid, 'admin', 'hr.applicant', 'unlink', [existing])
    
    # 2. Record max ID (anti-gaming: ensure we find a NEW record later)
    # We search all to find the max ID
    all_ids = models.execute_kw(db, uid, 'admin', 'hr.applicant', 'search', [[]])
    max_id = max(all_ids) if all_ids else 0
    
    with open('/tmp/initial_max_id.txt', 'w') as f:
        f.write(str(max_id))
        
    print(f"Setup complete. Initial max applicant ID: {max_id}")

except Exception as e:
    print(f"Error during setup: {e}", file=sys.stderr)
    # Write 0 as fallback
    with open('/tmp/initial_max_id.txt', 'w') as f:
        f.write("0")
PYTHON_EOF

# Launch Firefox and navigate to Recruitment app
# This helps the agent start in the right context
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job_sources"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== create_job_application task setup complete ==="