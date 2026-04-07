#!/bin/bash
echo "=== Exporting Communicate Meeting Update result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START_TIMESTAMP=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Extract data from Odoo via Python/XML-RPC
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'
task_start_ts = float($TASK_START_TIMESTAMP)

result_data = {
    "event_found": False,
    "description": "",
    "messages": [],
    "task_start_ts": task_start_ts
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Fetch the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                               [[['name', '=', 'Q2 Financial Review']]],
                               {'fields': ['id', 'description'], 'limit': 1})
    
    if events:
        event = events[0]
        result_data["event_found"] = True
        # Odoo descriptions are often HTML; we keep raw for verifier to parse
        result_data["description"] = event.get('description') or ""
        event_id = event['id']

        # 2. Fetch messages linked to this event
        # We look for messages created roughly after task start
        # Note: 'date' in mail.message is UTC string. 
        # We fetch ALL messages for this ID and filter in Python to be safe regarding TZ.
        messages = models.execute_kw(db, uid, password, 'mail.message', 'search_read',
                                     [[['model', '=', 'calendar.event'], 
                                       ['res_id', '=', event_id]]],
                                     {'fields': ['date', 'body', 'message_type', 'author_id', 'subtype_id']})
        
        # Sort by date descending
        messages.sort(key=lambda x: x['date'], reverse=True)
        
        result_data["messages"] = messages
        print(f"Found {len(messages)} messages for event {event_id}")

except Exception as e:
    result_data["error"] = str(e)
    print(f"Export error: {e}", file=sys.stderr)

# Write to JSON
with open(output_file, 'w') as f:
    json.dump(result_data, f, indent=2)

print(f"Data exported to {output_file}")
PYTHON_EOF

# Set permissions so verifier can copy it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="