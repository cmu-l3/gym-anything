#!/bin/bash
echo "=== Exporting finalize_tentative_schedule result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query the database state of the specific events
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
ids_file = '/tmp/task_event_ids.json'
output_file = '/tmp/task_result.json'

result = {
    "setup_valid": False,
    "tue_exists": False,
    "wed_exists": False,
    "thu_exists": False,
    "wed_data": {},
    "unexpected_events_count": 0
}

try:
    if not os.path.exists(ids_file):
        print("IDs file not found.")
    else:
        with open(ids_file, 'r') as f:
            setup_data = json.load(f)
            
        tue_id = setup_data['tue_id']
        wed_id = setup_data['wed_id']
        thu_id = setup_data['thu_id']
        expected_wed_start = setup_data['wed_expected_start']
        
        result["setup_valid"] = True
        result["expected_wed_start"] = expected_wed_start

        # Connect to Odoo
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # Check Tuesday Event
        # We search specifically for the ID to see if it exists
        # 'exists' method in Odoo is implied by search or read success
        tue_read = models.execute_kw(db, uid, password, 'calendar.event', 'read', [[tue_id], ['name', 'active']])
        # If read returns empty list, it's deleted. If active=False, it's archived (effectively deleted for calendar)
        if tue_read:
            result["tue_exists"] = True
            result["tue_active"] = tue_read[0].get('active', True)
        
        # Check Thursday Event
        thu_read = models.execute_kw(db, uid, password, 'calendar.event', 'read', [[thu_id], ['name', 'active']])
        if thu_read:
            result["thu_exists"] = True
            result["thu_active"] = thu_read[0].get('active', True)

        # Check Wednesday Event (The Winner)
        wed_read = models.execute_kw(db, uid, password, 'calendar.event', 'read', [[wed_id], ['name', 'active', 'start', 'location']])
        if wed_read:
            result["wed_exists"] = True
            result["wed_data"] = wed_read[0]
            
        # Check for any rogue "Hold" events remaining (anti-gaming: did they just create new ones or fail to delete?)
        remaining_holds = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', 
            [[['name', 'ilike', 'Hold: Q3 Budget Review']]])
        result["remaining_holds_count"] = remaining_holds

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    result["error"] = str(e)

# Save result to JSON
with open(output_file, 'w') as f:
    json.dump(result, f)

print(f"Exported result to {output_file}")
PYTHON_EOF

# Fix permissions just in case
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="