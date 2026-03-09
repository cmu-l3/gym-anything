#!/bin/bash
echo "=== Setting up set_meeting_reminder task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "set_meeting_reminder"

# Find event ID and clear any existing reminders
EVENT_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                               [[['name', '=', 'Q2 Financial Review']]])
    if events:
        # Clear any existing alarm_ids so task is always fresh
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'write',
                          [events, {'alarm_ids': [(5, 0, 0)]}])
        print(events[0])
    else:
        print("WARNING: 'Q2 Financial Review' event not found", file=sys.stderr)
        print('')
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    print('')
PYTHON_EOF
)

echo "Q2 Financial Review event_id=$EVENT_ID"

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$EVENT_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$EVENT_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/task_start.png

echo "Task start state: 'Q2 Financial Review' event form is shown (no reminder set)."
echo "Agent should add a 30-minute email reminder to this event and save."
echo "=== set_meeting_reminder task setup complete ==="
