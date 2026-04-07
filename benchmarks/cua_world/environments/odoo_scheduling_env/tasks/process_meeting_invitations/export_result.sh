#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the status of the specific events
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'
result_file = '/tmp/task_result.json'

try:
    # Get IDs from setup
    event_ids = []
    if os.path.exists('/tmp/task_event_ids.txt'):
        with open('/tmp/task_event_ids.txt', 'r') as f:
            for line in f:
                if line.strip():
                    event_ids.append(int(line.strip()))
    
    if len(event_ids) < 2:
        # Fallback search if file missing
        print("Warning: Event IDs file missing or incomplete, searching by name...", file=sys.stderr)
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', 
            [[['name', 'in', ['Project Alpha Sync', 'Vendor Cold Call']]]])

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get Admin partner ID
    user_data = models.execute_kw(db, uid, password, 'res.users', 'read', [uid], {'fields': ['partner_id']})
    partner_id = user_data[0]['partner_id'][0]

    # Fetch event details to map ID to Name
    events = models.execute_kw(db, uid, password, 'calendar.event', 'read', [event_ids], {'fields': ['name']})
    
    event_status = {}
    
    for event in events:
        # Find attendee record for this event + admin
        attendee_ids = models.execute_kw(db, uid, password, 'calendar.attendee', 'search', 
            [[['event_id', '=', event['id']], ['partner_id', '=', partner_id]]])
        
        status = 'unknown'
        if attendee_ids:
            attendee = models.execute_kw(db, uid, password, 'calendar.attendee', 'read', [attendee_ids[0]], {'fields': ['state']})
            status = attendee[0]['state']
            
        event_status[event['name']] = {
            'id': event['id'],
            'status': status,
            'exists': True
        }

    # Prepare result
    output = {
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "events": event_status,
        "screenshot_path": "/tmp/task_final.png"
    }

    with open(result_file, 'w') as f:
        json.dump(output, f)
        
    print(json.dumps(output, indent=2))

except Exception as e:
    print(f"Error exporting results: {e}", file=sys.stderr)
    # Save error state
    with open(result_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="