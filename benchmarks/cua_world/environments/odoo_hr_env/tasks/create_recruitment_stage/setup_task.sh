#!/bin/bash
set -e
echo "=== Setting up create_recruitment_stage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Record initial state of recruitment stages
# We save the count and the specific sequence of relevant stages to detect changes later.
echo "Recording initial database state..."
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Get all stages
    stages = models.execute_kw(db, uid, 'admin', 'hr.recruitment.stage', 'search_read',
                               [[]], 
                               {'fields': ['id', 'name', 'sequence']})
    
    count = len(stages)
    
    # Save to file
    with open('/tmp/initial_state.json', 'w') as f:
        json.dump({
            'count': count,
            'stages': stages
        }, f)
        
    print(f"Recorded {count} initial stages.")

    # Clean up any previous attempts if they exist (idempotency)
    # If 'Technical Assessment' exists from a previous run, delete it to ensure a clean start
    existing_id = models.execute_kw(db, uid, 'admin', 'hr.recruitment.stage', 'search',
                                    [[['name', '=', 'Technical Assessment']]])
    if existing_id:
        models.execute_kw(db, uid, 'admin', 'hr.recruitment.stage', 'unlink', [existing_id])
        print("Removed existing 'Technical Assessment' stage from previous run.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# 2. Launch Firefox and navigate to the Recruitment Kanban view
# This puts the agent in the correct starting context
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"

# 3. Take initial screenshot
echo "Capturing initial state..."
sleep 2 # Wait for render
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="