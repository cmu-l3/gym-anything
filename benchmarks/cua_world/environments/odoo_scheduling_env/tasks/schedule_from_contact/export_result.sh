#!/bin/bash
echo "=== Exporting schedule_from_contact results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture Odoo state via Python XML-RPC
python3 << 'EOF'
import xmlrpc.client
import json
import sys
import time
from datetime import datetime, timedelta

# Odoo Connection Details
url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "event_found": False,
    "event_data": {},
    "attendees_found": [],
    "target_attendees_ids": {},
    "system_date": datetime.now().strftime('%Y-%m-%d'),
    "task_start_ts": 0,
    "initial_count": 0,
    "current_count": 0
}

try:
    # Load baselines
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start_ts'] = int(f.read().strip())
    except: pass
    
    try:
        with open('/tmp/initial_event_count.txt', 'r') as f:
            result['initial_count'] = int(f.read().strip())
    except: pass

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    result['current_count'] = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[]])

    # Get Partner IDs for validation
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search_read',
        [[['name', 'in', ['Grace Patel', 'Frank Rivera']]]],
        {'fields': ['id', 'name']})
    
    for p in partners:
        result['target_attendees_ids'][p['name']] = p['id']

    # Search for the specific event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Q2 Performance Debrief with CFO']]],
        {'fields': ['name', 'start', 'stop', 'location', 'description', 'partner_ids', 'create_date']})

    if events:
        evt = events[0]
        result['event_found'] = True
        result['event_data'] = evt
        
        # Check attendees
        evt_partners = evt.get('partner_ids', [])
        found_names = []
        # partner_ids in Odoo search_read usually returns list of IDs [1, 2]
        # map back to names using our lookup
        id_to_name = {v: k for k, v in result['target_attendees_ids'].items()}
        
        for pid in evt_partners:
            if pid in id_to_name:
                found_names.append(id_to_name[pid])
        
        result['attendees_found'] = found_names

except Exception as e:
    result['error'] = str(e)

# Save result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="