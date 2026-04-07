#!/bin/bash
set -e
echo "=== Setting up Communicate Meeting Update task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (messages must be sent AFTER this)
date +%s > /tmp/task_start_time.txt
# Also save a formatted string for Python/Odoo comparisons if needed, 
# though usually we compare timestamps.
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_iso.txt

# Reset the specific event to a known clean state
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                               [[['name', '=', 'Q2 Financial Review']]],
                               {'fields': ['id', 'name'], 'limit': 1})
    
    if not events:
        print("ERROR: 'Q2 Financial Review' event not found!", file=sys.stderr)
        sys.exit(1)

    event_id = events[0]['id']
    print(f"Found event ID: {event_id}")

    # Reset description to generic text
    models.execute_kw(db, uid, password, 'calendar.event', 'write',
                      [[event_id], {'description': '<p>Regular quarterly review.</p>'}])
    
    print("Event description reset.")

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="