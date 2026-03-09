#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Reassign Sales Activities Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the state of the activities
python3 - <<PYEOF
import xmlrpc.client
import json
import os
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

output = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "activities": [],
    "ellis_pending_count": -1,
    "user_map": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, passwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get User IDs
    users = models.execute_kw(db, uid, passwd, 'res.users', 'search_read', 
        [[['login', 'in', ['ellis', 'sam']]]], 
        {'fields': ['id', 'name', 'login']})
    
    user_map = {u['login']: u['id'] for u in users}
    ellis_id = user_map.get('ellis')
    sam_id = user_map.get('sam')
    output["user_map"] = user_map

    # 1. Check the specific activities we created
    # We look them up by summary since IDs might persist but helpful to cross-check
    target_summaries = ["Contract Negotiation", "Pricing Update", "Prepare Demo"]
    
    # Read timestamps too for anti-gaming
    activities = models.execute_kw(db, uid, passwd, 'mail.activity', 'search_read',
        [[['summary', 'in', target_summaries]]],
        {'fields': ['id', 'summary', 'user_id', 'write_date', 'create_date']})
    
    for act in activities:
        # Odoo returns user_id as [id, "Name"] or just id sometimes
        uid_val = act['user_id'][0] if isinstance(act['user_id'], list) else act['user_id']
        uid_name = act['user_id'][1] if isinstance(act['user_id'], list) else "Unknown"
        
        output["activities"].append({
            "id": act['id'],
            "summary": act['summary'],
            "assigned_user_id": uid_val,
            "assigned_user_name": uid_name,
            "write_date": act['write_date']
        })

    # 2. Check if Ellis has ANY pending activities left
    if ellis_id:
        ellis_count = models.execute_kw(db, uid, passwd, 'mail.activity', 'search_count',
            [[['user_id', '=', ellis_id]]])
        output["ellis_pending_count"] = ellis_count

except Exception as e:
    output["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

# Write result to temp file
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(output, f, indent=2)

PYEOF

# Move result to safe location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json