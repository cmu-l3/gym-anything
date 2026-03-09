#!/bin/bash
echo "=== Setting up add_meeting_description task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "add_meeting_description"

# Find event ID and clear description
EVENT_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                               [[['name', '=', 'Annual Performance Review - Frank Rivera']]])
    if events:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'write',
                          [events, {'description': False}])
        print(events[0])
    else:
        print("WARNING: 'Annual Performance Review - Frank Rivera' event not found", file=sys.stderr)
        print('')
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    print('')
PYTHON_EOF
)

echo "Annual Performance Review - Frank Rivera event_id=$EVENT_ID"

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$EVENT_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$EVENT_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/task_start.png

echo "Task start state: 'Annual Performance Review - Frank Rivera' event form is shown (no description)."
echo "Agent should add description: 'Discuss 2025 performance metrics, goal achievement, and set objectives for 2026.' and save."
echo "=== add_meeting_description task setup complete ==="
