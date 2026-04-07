#!/bin/bash
set -e
echo "=== Setting up task: manage_job_recruitment_lifecycle ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running
if ! pgrep -f "odoo-bin" > /dev/null && ! docker ps | grep -q "odoo"; then
    echo "Odoo not running, waiting..."
    sleep 5
fi

# Set initial state via Python XML-RPC:
# - Consultant: State = recruit (so agent has to stop it)
# - Trainee: State = open (so agent has to start it), Target != 3, Recruiter != Mitchell Admin
python3 << 'PYEOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Auth failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Setup Consultant (Ensure it is RECRUITING)
    # Search for existing or create
    consultant_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Consultant']]])
    if not consultant_ids:
        consultant_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Consultant'}])
        consultant_ids = [consultant_id]
    
    # Force state to recruit
    models.execute_kw(db, uid, password, 'hr.job', 'write', [consultant_ids, {'state': 'recruit'}])
    print("Consultant set to RECRUIT")

    # 2. Setup Trainee (Ensure it is NOT RECRUITING)
    trainee_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Trainee']]])
    if not trainee_ids:
        trainee_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Trainee'}])
        trainee_ids = [trainee_id]

    # Force state to open (Stopped), Target=1, Recruiter=False (or anyone else)
    models.execute_kw(db, uid, password, 'hr.job', 'write', [trainee_ids, {
        'state': 'open',
        'no_of_recruitment': 1,
        'user_id': False
    }])
    print("Trainee set to OPEN (Stopped), Target=1, Recruiter=None")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# Launch Firefox to the Recruitment app (Kanban view)
# This gives the agent a clear starting point
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="