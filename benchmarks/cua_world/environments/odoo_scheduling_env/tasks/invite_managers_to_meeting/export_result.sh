#!/bin/bash
echo "=== Exporting invite_managers_to_meeting result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the final state of the event
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "event_found": False,
    "attendee_names": [],
    "write_date": "",
    "task_start": 0,
    "task_end": 0
}

try:
    # Load timestamps
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start'] = int(f.read().strip())
    except:
        pass
    
    result['task_end'] = int(time.time())

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                               [[['name', '=', 'Q2 Financial Review']]],
                               {'fields': ['partner_ids', 'write_date']})

    if events:
        event = events[0]
        result['event_found'] = True
        result['write_date'] = event['write_date']
        
        # Resolve partner IDs to names
        partner_ids = event['partner_ids']
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                                       [partner_ids], {'fields': ['name']})
            result['attendee_names'] = [p['name'] for p in partners]

except Exception as e:
    result['error'] = str(e)

# Write result to temp file
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f)

PYTHON_EOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="