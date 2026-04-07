#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (visual evidence)
take_screenshot /tmp/task_final.png

# 2. Extract Data from Odoo Database
# We query for the specific event created by the agent.
# We fetch details to verify: name, start, duration, location, description, attendees.

python3 << 'PYTHON_EOF' > /tmp/task_result.json
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "found": False,
    "event": {},
    "attendee_names": [],
    "error": None
}

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Read task start time to verify creation happened during task
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            task_start_ts = float(f.read().strip())
    except:
        task_start_ts = 0

    # Search for the event
    # We filter by name and ensure it was created/modified recently
    domain = [['name', 'ilike', 'System Architecture Review']]
    fields = ['name', 'start', 'stop', 'duration', 'location', 'description', 'partner_ids', 'create_date', 'write_date']
    
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', [domain], {'fields': fields, 'limit': 1})

    if events:
        event = events[0]
        result['found'] = True
        result['event'] = event
        
        # Get Attendee Names from partner_ids
        partner_ids = event.get('partner_ids', [])
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [partner_ids], {'fields': ['name']})
            result['attendee_names'] = [p['name'] for p in partners]
        
        # Verify timestamps (anti-gaming)
        # Odoo dates are strings 'YYYY-MM-DD HH:MM:SS'
        create_date_str = event.get('create_date')
        if create_date_str:
            create_dt = datetime.datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
            # Assume Odoo server is UTC or local system time. 
            # We compare simple timestamps.
            # Convert to timestamp
            create_ts = create_dt.timestamp()
            # Allow some skew, but ensure it's not an old event
            result['created_during_task'] = create_ts >= (task_start_ts - 60)
        else:
             result['created_during_task'] = False

    else:
        result['found'] = False

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYTHON_EOF

# 3. Secure the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"