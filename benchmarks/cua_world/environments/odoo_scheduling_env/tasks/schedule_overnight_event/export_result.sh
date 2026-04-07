#!/bin/bash
echo "=== Exporting schedule_overnight_event result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the specific event
# We fetch start, stop, duration, and metadata
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "event_found": False,
    "event_data": {},
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the event
    # We look for created events after the task start to avoid stale data (though we cleaned up)
    # Note: Odoo stores dates in UTC. We fetch raw values.
    domain = [
        ['name', '=', 'Database Migration']
    ]
    
    fields = ['name', 'start', 'stop', 'duration', 'location', 'description', 'allday']
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', [domain], {'fields': fields, 'limit': 1})

    if events:
        event = events[0]
        result["event_found"] = True
        result["event_data"] = event
        print(f"Found event: {event['name']} (Duration: {event['duration']})")
    else:
        print("Event 'Database Migration' not found.")

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

# Write result to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYTHON_EOF

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="