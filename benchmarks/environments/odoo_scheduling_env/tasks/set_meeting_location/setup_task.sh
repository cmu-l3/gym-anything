#!/bin/bash
echo "=== Setting up set_meeting_location task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "set_meeting_location"

# Find event ID and clear location
EVENT_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                               [[['name', '=', 'Product Roadmap Planning']]])
    if events:
        # Clear location so the task always starts fresh
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'write',
                          [events, {'location': False}])
        print(events[0])
    else:
        print("WARNING: 'Product Roadmap Planning' event not found", file=sys.stderr)
        print('')
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    print('')
PYTHON_EOF
)

echo "Product Roadmap Planning event_id=$EVENT_ID"

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$EVENT_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$EVENT_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/task_start.png

echo "Task start state: 'Product Roadmap Planning' event form is shown (no location set)."
echo "Agent should set the location to 'Conference Room B' and save."
echo "=== set_meeting_location task setup complete ==="
