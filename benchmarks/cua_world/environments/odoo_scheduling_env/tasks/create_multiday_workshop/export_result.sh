#!/bin/bash
echo "=== Exporting create_multiday_workshop result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo and export result to JSON
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
output_file = '/tmp/task_result.json'

result = {
    "event_found": False,
    "event_details": {},
    "task_start_time": 0,
    "initial_event_count": 0,
    "final_event_count": 0,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    # Load task start info
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start_time'] = int(f.read().strip())
            
    if os.path.exists('/tmp/initial_event_count.txt'):
        with open('/tmp/initial_event_count.txt', 'r') as f:
            result['initial_event_count'] = int(f.read().strip())

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get final count
    result['final_event_count'] = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[]])

    # Search for the specific event
    # Using 'ilike' for case-insensitive partial match
    domain = [[['name', 'ilike', 'DevOps Workshop']]]
    fields = ['name', 'start', 'stop', 'allday', 'location', 'description', 'partner_ids', 'create_date']
    
    events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read', [domain], {'fields': fields, 'limit': 1, 'order': 'create_date desc'})

    if events:
        event = events[0]
        result['event_found'] = True
        result['event_details'] = event
        
        # Resolve attendee names
        if event.get('partner_ids'):
            attendees = models.execute_kw(db, uid, 'admin', 'res.partner', 'read', [event['partner_ids']], {'fields': ['name']})
            result['attendee_names'] = [a['name'] for a in attendees]
        else:
            result['attendee_names'] = []
            
    # Also dump all events created after task start for debugging/anti-gaming
    if result['task_start_time'] > 0:
        # Note: Odoo stores create_date in UTC. We'll fetch recent events.
        recent_events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read', 
            [[['create_date', '>=', datetime.fromtimestamp(result['task_start_time']).strftime('%Y-%m-%d %H:%M:%S')]]], 
            {'fields': ['name', 'create_date'], 'limit': 5})
        result['recent_events'] = recent_events

except Exception as e:
    result['error'] = str(e)
    print(f"Error exporting result: {e}", file=sys.stderr)

# Write result to JSON
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {output_file}")
PYTHON_EOF

# Set permissions so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="