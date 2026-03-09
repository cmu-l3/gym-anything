#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up archive_stale_opportunities task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Create the three stale opportunities and record initial state via Python/XMLRPC
# We use Python for precise control over the Odoo models
python3 - << 'PYEOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)

    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get the "New" stage
    stages = models.execute_kw(db, uid, password, 'crm.stage', 'search_read',
        [[]], {'fields': ['id', 'name'], 'order': 'sequence', 'limit': 1})
    new_stage_id = stages[0]['id'] if stages else False

    opportunities = [
        {
            'name': 'Cloud Migration Assessment - GlobalTech Solutions',
            'partner_name': 'GlobalTech Solutions',
            'type': 'opportunity',
            'expected_revenue': 75000,
            'probability': 10,
            'stage_id': new_stage_id,
            'description': 'Prospect evaluating cloud migration. Last contact 3 months ago - chose competitor.',
        },
        {
            'name': 'POS System Rollout - Bay Area Retailers',
            'partner_name': 'Bay Area Retailers',
            'type': 'opportunity',
            'expected_revenue': 42000,
            'probability': 5,
            'stage_id': new_stage_id,
            'description': 'Multi-location POS deployment. Prospect unresponsive for 3 months.',
        },
        {
            'name': 'Data Analytics Platform - Meridian Corp',
            'partner_name': 'Meridian Corp',
            'type': 'opportunity',
            'expected_revenue': 120000,
            'probability': 15,
            'stage_id': new_stage_id,
            'description': 'Enterprise analytics solution. Project cancelled by prospect due to budget cuts.',
        },
    ]

    for opp in opportunities:
        # Check if already exists (search including inactive to avoid duplicates)
        existing = models.execute_kw(db, uid, password, 'crm.lead', 'search',
            [[['name', '=', opp['name']]]],
            {'context': {'active_test': False}})
        
        if not existing:
            new_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [opp])
            print(f"Created: {opp['name']} (ID: {new_id})")
        else:
            # Ensure it's active for the task start
            models.execute_kw(db, uid, password, 'crm.lead', 'write',
                [existing, {'active': True, 'stage_id': new_stage_id}])
            print(f"Reset to active: {opp['name']} (ID: {existing[0]})")

    # Force a small sleep to ensure DB commits before counting
    time.sleep(1)

    # Record initial count of ALL active opportunities
    # This is critical for the collateral damage check
    all_active_count = models.execute_kw(db, uid, password, 'crm.lead', 'search_count',
        [[['type', '=', 'opportunity'], ['active', '=', True]]])
    
    print(f"Initial active opportunity count: {all_active_count}")
    
    with open('/tmp/initial_active_count.txt', 'w') as f:
        f.write(str(all_active_count))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure we are logged in and at the Pipeline
ensure_odoo_logged_in "$CRM_PIPELINE_URL"
sleep 2

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot taken"

echo "=== Task setup complete ==="