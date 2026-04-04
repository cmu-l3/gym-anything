#!/bin/bash
echo "=== Exporting delete_pipeline_stage results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export result data using Python XML-RPC
python3 - <<'PYEOF'
import xmlrpc.client
import json
import os
import time

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"
output_file = "/tmp/task_result.json"

result = {
    "stage_deleted": False,
    "opps_moved_correctly": False,
    "opp_statuses": {},
    "timestamp": time.time()
}

try:
    # Read setup IDs to know what to check
    setup_data = {}
    if os.path.exists('/tmp/setup_ids.txt'):
        with open('/tmp/setup_ids.txt', 'r') as f:
            for line in f:
                if '=' in line:
                    key, val = line.strip().split('=', 1)
                    setup_data[key] = val
    
    stage_id_initial = int(setup_data.get('stage_id', 0))
    target_stage_id = int(setup_data.get('new_stage_id', 0))
    
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # CHECK 1: Is the 'Initial Review' stage deleted?
    # Check by ID (should be gone)
    stage_exists_id = models.execute_kw(db, uid, password, 'crm.stage', 'search', [[['id', '=', stage_id_initial]]])
    # Check by Name (should be gone)
    stage_exists_name = models.execute_kw(db, uid, password, 'crm.stage', 'search', [[['name', '=', 'Initial Review']]])
    
    result['stage_deleted'] = (not stage_exists_id) and (not stage_exists_name)
    result['stage_exists_debug'] = f"ID_found={bool(stage_exists_id)}, Name_found={bool(stage_exists_name)}"

    # CHECK 2: Are opportunities moved to 'New'?
    opp_names = ['Acme Corp Server Upgrade', 'GlobalTech Cloud Migration']
    all_moved = True
    
    for name in opp_names:
        # Search for the opportunity
        opps = models.execute_kw(db, uid, password, 'crm.lead', 'search_read', 
            [[['name', '=', name]]], {'fields': ['stage_id', 'name']})
        
        if not opps:
            result['opp_statuses'][name] = "missing"
            all_moved = False
            continue
            
        opp = opps[0]
        # stage_id returns [id, "Name"]
        current_stage_id = opp['stage_id'][0] if opp['stage_id'] else None
        current_stage_name = opp['stage_id'][1] if opp['stage_id'] else "None"
        
        status = {
            "current_stage_id": current_stage_id,
            "current_stage_name": current_stage_name,
            "is_correct": (current_stage_id == target_stage_id) or (current_stage_name == "New")
        }
        result['opp_statuses'][name] = status
        
        if not status['is_correct']:
            all_moved = False

    result['opps_moved_correctly'] = all_moved

except Exception as e:
    result['error'] = str(e)

# Write result to JSON file
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {output_file}")
PYEOF

# Ensure permissions for the file so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="