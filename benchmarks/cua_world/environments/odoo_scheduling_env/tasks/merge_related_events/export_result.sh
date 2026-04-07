#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Odoo for Final State
# We need to export:
# - Whether the new merged event exists and its details (attendees, location, description)
# - Whether the original events still exist (should be 0)
# - Timestamps to verify creation happened during task

python3 << 'PYTHON_EOF' > /tmp/task_result.json
import xmlrpc.client
import json
import os
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "merged_event_found": False,
    "merged_event_details": {},
    "original_events_remaining": [],
    "task_start_ts": 0,
    "merged_event_create_date": ""
}

try:
    # Get task start time
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start_ts'] = float(f.read().strip())

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check for Merged Event
    target_name = "Product & Engineering Joint Review"
    # Search specifically for the name
    merged_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[['name', 'ilike', target_name]]])
    
    if merged_ids:
        # Get details of the most recently created one
        events = models.execute_kw(db, uid, password, 'calendar.event', 'read', [merged_ids, ['name', 'location', 'description', 'partner_ids', 'start', 'stop', 'duration', 'create_date']])
        # Sort by create_date desc
        events.sort(key=lambda x: x['create_date'], reverse=True)
        event = events[0]
        
        result['merged_event_found'] = True
        result['merged_event_details'] = {
            'name': event.get('name'),
            'location': event.get('location'),
            'description': event.get('description'),
            'duration': event.get('duration'),
            'create_date': event.get('create_date'),
            'attendee_names': []
        }
        
        # Resolve partner IDs to names
        if event.get('partner_ids'):
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [event['partner_ids'], ['name']])
            result['merged_event_details']['attendee_names'] = [p['name'] for p in partners]

    # Check for Original Events (should be deleted)
    originals = ["Product Strategy Review", "Engineering Architecture Discussion"]
    remaining = []
    for name in originals:
        ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[['name', '=', name]]])
        if ids:
            remaining.append(name)
    
    result['original_events_remaining'] = remaining

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result, indent=2))
PYTHON_EOF

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json