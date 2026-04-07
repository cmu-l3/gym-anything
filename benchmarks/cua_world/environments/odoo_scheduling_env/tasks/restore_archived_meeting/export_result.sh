#!/bin/bash
echo "=== Exporting Restore Archived Meeting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ID=$(cat /tmp/target_event_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the state of the specific event and any potential duplicates
python3 << PYTHON_EOF
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
target_id = int("$TARGET_ID")
task_start = float("$TASK_START")

result_data = {
    "target_event_found": False,
    "target_event_active": False,
    "target_event_description": "",
    "duplicate_count": 0,
    "newly_created_count": 0,
    "task_start_ts": task_start,
    "timestamp": datetime.now().isoformat()
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check the specific target event (we know its ID from setup)
    # We must include ['active', 'in', [True, False]] to find it regardless of state
    target_event = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', 
                                   [[['id', '=', target_id], '|', ['active', '=', True], ['active', '=', False]]], 
                                   {'fields': ['name', 'active', 'description', 'partner_ids']})
    
    if target_event:
        evt = target_event[0]
        result_data['target_event_found'] = True
        result_data['target_event_active'] = evt.get('active', False)
        result_data['target_event_description'] = evt.get('description', '')
        result_data['target_event_partners'] = evt.get('partner_ids', [])

    # Check for duplicates or cheating (creating a NEW event instead of restoring)
    # Search for ANY event with the same name
    all_events_with_name = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                                           [[['name', '=', 'Q3 Board Prep'], '|', ['active', '=', True], ['active', '=', False]]],
                                           {'fields': ['id', 'create_date', 'active']})
    
    result_data['duplicate_count'] = len(all_events_with_name)
    
    # Check if any of these are "new" (created after task start)
    # create_date in Odoo is typically string "YYYY-MM-DD HH:MM:SS"
    for evt in all_events_with_name:
        if evt['id'] != target_id:
            # It's not the original event. Is it new?
            # We assume if it's not the target ID, it's a potential duplicate
            pass
            
        # Odoo dates are UTC. Simple check: if ID > target_id, it was created later
        if evt['id'] > target_id:
            result_data['newly_created_count'] += 1

except Exception as e:
    result_data["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

# Write result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

print("Exported data:")
print(json.dumps(result_data, indent=2))
PYTHON_EOF

# Set permissions so the host can read it (via copy_from_env)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="