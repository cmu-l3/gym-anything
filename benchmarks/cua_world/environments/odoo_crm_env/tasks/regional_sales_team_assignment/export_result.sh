#!/bin/bash
echo "=== Exporting Regional Sales Team Assignment Result ==="

source /workspace/scripts/task_utils.sh

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final screenshot
take_screenshot /tmp/task_final.png

# 3. Query Database State via Python/XMLRPC
# We export a JSON with all relevant data for the verifier
python3 - <<PYEOF
import xmlrpc.client
import json
import os
import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "team_created": False,
    "team_data": {},
    "assignments": {},
    "errors": []
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # --- Check Team Creation ---
    # Search for team named "West Coast"
    teams = models.execute_kw(db, uid, password, 'crm.team', 'search_read', 
        [[['name', '=', 'West Coast']]], 
        {'fields': ['id', 'name', 'user_id', 'create_date']})
    
    if teams:
        result["team_created"] = True
        result["team_data"] = teams[0]
        west_coast_id = teams[0]['id']
    else:
        west_coast_id = -1

    # --- Check Assignments ---
    # Define the leads we are tracking
    leads_to_check = [
        'Golden Gate Software Upgrade', 
        'SoCal Surf Shop Franchise', 
        'Napa Valley Logistics',
        'Gotham Trading Platform', 
        'Austin Warehouse Automation'
    ]

    leads = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', 'in', leads_to_check]]],
        {'fields': ['name', 'team_id', 'write_date']})

    for lead in leads:
        # team_id is a tuple (id, name) or False
        team_info = lead.get('team_id')
        team_id = team_info[0] if team_info else False
        team_name = team_info[1] if team_info else "Unassigned"
        
        result["assignments"][lead['name']] = {
            "team_id": team_id,
            "team_name": team_name,
            "is_west_coast": (team_id == west_coast_id),
            "write_date": lead.get('write_date')
        }

except Exception as e:
    result["errors"].append(str(e))

# Write to temp file
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# 4. Secure Move to Final Location
# Handle permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/result_temp.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="