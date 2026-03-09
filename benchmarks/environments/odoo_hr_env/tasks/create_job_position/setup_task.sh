#!/bin/bash
echo "=== Setting up create_job_position task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing "Data Scientist" job position
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'hr.job', 'search',
                                 [[['name', '=', 'Data Scientist']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'hr.job', 'unlink', [existing])
        print(f"Removed existing job position 'Data Scientist' (ids={existing})")
    else:
        print("No existing 'Data Scientist' job position — clean slate")
    # Show existing job positions for reference
    jobs = models.execute_kw(db, uid, 'admin', 'hr.job', 'search_read',
                             [[]], {'fields': ['name', 'department_id'], 'limit': 10})
    print(f"Current job positions: {[j['name'] for j in jobs]}")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Job Positions list
ensure_firefox "http://localhost:8069/web#action=hr.action_hr_job"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Job Positions list (Odoo official demo data)."
echo "Agent should create 'Data Scientist' in Research & Development."
echo "=== create_job_position task setup complete ==="
