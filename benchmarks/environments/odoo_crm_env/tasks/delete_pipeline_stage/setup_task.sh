#!/bin/bash
set -e
echo "=== Setting up delete_pipeline_stage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Use Python to set up the database state (clean & predictable)
python3 - <<'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # 1. Ensure 'New' stage exists and get its ID
    new_stage = models.execute_kw(db, uid, password, 'crm.stage', 'search_read',
        [[['name', '=', 'New']]], {'fields': ['id', 'sequence'], 'limit': 1})
    
    if not new_stage:
        # Fallback if New doesn't exist (unlikely in standard install)
        print("Creating 'New' stage...")
        new_id = models.execute_kw(db, uid, password, 'crm.stage', 'create', [{'name': 'New', 'sequence': 0}])
        new_sequence = 0
    else:
        new_id = new_stage[0]['id']
        new_sequence = new_stage[0]['sequence']

    # 2. Cleanup: Remove 'Initial Review' stage if it exists from previous runs
    old_stages = models.execute_kw(db, uid, password, 'crm.stage', 'search', [[['name', '=', 'Initial Review']]])
    if old_stages:
        # Move any leads out of it first to allow deletion
        leads_in_stage = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['stage_id', 'in', old_stages]]])
        if leads_in_stage:
            models.execute_kw(db, uid, password, 'crm.lead', 'write', [leads_in_stage, {'stage_id': new_id}])
        
        models.execute_kw(db, uid, password, 'crm.stage', 'unlink', [old_stages])
        print("Cleaned up existing 'Initial Review' stage")

    # 3. Create 'Initial Review' stage (sequence slightly higher than New)
    stage_id = models.execute_kw(db, uid, password, 'crm.stage', 'create', 
        [{'name': 'Initial Review', 'sequence': new_sequence + 1}])
    print(f"Created 'Initial Review' stage (ID: {stage_id})")

    # 4. Create Opportunities in 'Initial Review'
    opps = [
        {'name': 'Acme Corp Server Upgrade', 'expected_revenue': 50000},
        {'name': 'GlobalTech Cloud Migration', 'expected_revenue': 120000}
    ]
    
    opp_ids = []
    for opp in opps:
        # Clean up existing opps with same name
        existing = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', opp['name']]]])
        if existing:
            models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing])
            
        # Create new
        oid = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
            'name': opp['name'],
            'type': 'opportunity',
            'stage_id': stage_id,
            'expected_revenue': opp['expected_revenue'],
            'probability': 20
        }])
        opp_ids.append(oid)
        print(f"Created opportunity '{opp['name']}' (ID: {oid})")

    # Save IDs to file for verification later
    with open('/tmp/setup_ids.txt', 'w') as f:
        f.write(f"stage_id={stage_id}\n")
        f.write(f"new_stage_id={new_id}\n")
        f.write(f"opp_ids={','.join(map(str, opp_ids))}\n")

except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in, navigate to CRM Pipeline
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="