#!/bin/bash
set -e
echo "=== Setting up convert_meeting_to_recurring_schedule task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the "Team Standup" event exists and is NOT recurring
# We use Python to reset it to a known state just in case
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, datetime
from datetime import timedelta

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
                               [[['name', '=', 'Team Standup']]],
                               {'fields': ['id', 'recurrence_id', 'start']})
    
    if not events:
        print("Error: 'Team Standup' event not found!", file=sys.stderr)
        sys.exit(1)

    event_id = events[0]['id']
    
    # If it is already recurring (from a previous failed run?), strip the recurrence
    if events[0]['recurrence_id']:
        print(f"Resetting recurrence for event {event_id}...")
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
                          [[event_id], {'recurrence_id': False}])
        # Optionally delete the old recurrence rule to be clean, but unlinking the event is usually enough
    
    print(f"Setup complete. Event ID: {event_id}")

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="