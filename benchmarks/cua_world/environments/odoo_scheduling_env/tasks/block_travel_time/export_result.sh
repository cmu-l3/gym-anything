#!/bin/bash
echo "=== Exporting block_travel_time results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (evidence of visual state)
take_screenshot /tmp/task_final.png

# Export calendar state to JSON via Python XML-RPC
# We export the anchor event and the candidate travel events
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

def serialize(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    return str(obj)

output_data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "anchor_event": None,
    "pre_events": [],
    "post_events": []
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch Anchor Event
    anchor_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Client Onboarding - Isabel Santos']]])
    
    if anchor_ids:
        # Read start, stop, location
        anchor_data = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [anchor_ids, ['name', 'start', 'stop', 'location', 'duration']])
        if anchor_data:
            output_data['anchor_event'] = anchor_data[0]

    # Fetch "Travel to Client" events created after task start
    pre_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'ilike', 'Travel to Client']]])
        
    if pre_ids:
        pre_data = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [pre_ids, ['name', 'start', 'stop', 'location', 'duration', 'create_date']])
        output_data['pre_events'] = pre_data

    # Fetch "Return Travel" events created after task start
    post_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'ilike', 'Return Travel']]])
        
    if post_ids:
        post_data = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [post_ids, ['name', 'start', 'stop', 'location', 'duration', 'create_date']])
        output_data['post_events'] = post_data

except Exception as e:
    output_data['error'] = str(e)

# Save to temporary file with safe permissions
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(output_data, f, default=serialize, indent=2)

PYTHON_EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"