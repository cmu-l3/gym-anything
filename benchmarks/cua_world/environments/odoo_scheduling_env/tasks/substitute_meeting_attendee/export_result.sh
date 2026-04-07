#!/bin/bash
echo "=== Exporting substitute_meeting_attendee result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_EVENT_ID=$(cat /tmp/initial_event_id.txt 2>/dev/null || echo "0")

# Use Python to query the final state of the event
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "event_found": False,
    "attendees": [],
    "event_id_match": False,
    "write_date": "",
    "create_date": ""
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the event by name to see what currently exists
    event_name = "Marketing Campaign Review"
    # We fetch partner_ids (Many2many) which gives us IDs
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', event_name]]],
        {'fields': ['id', 'partner_ids', 'write_date', 'create_date']})

    if events:
        event = events[0]
        result["event_found"] = True
        result["event_id"] = event['id']
        result["event_id_match"] = (str(event['id']) == "$INITIAL_EVENT_ID")
        result["write_date"] = event['write_date']
        result["create_date"] = event['create_date']

        # Resolve partner IDs to Names for easier verification
        if event['partner_ids']:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'search_read',
                [[['id', 'in', event['partner_ids']]]],
                {'fields': ['name']})
            result["attendees"] = [p['name'] for p in partners]
        
except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}", file=sys.stderr)

# Write result to file
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported data to {output_file}")
PYTHON_EOF

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ensure permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="