#!/bin/bash
echo "=== Setting up investor_meeting_update task ==="

source /workspace/scripts/task_utils.sh

# Reset the 'Investor Update Preparation' event to its baseline state:
# - Remove Karen Lee from attendees (agent must find and add the Legal Counsel)
# - Clear location (agent must set to Board Room)
# - Clear description (agent must write an agenda)
# - Remove all alarms (agent must set a reminder)
EVENT_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the event
    event_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                  [[['name', '=', 'Investor Update Preparation']]])
    if not event_ids:
        print("ERROR: 'Investor Update Preparation' event not found", file=sys.stderr)
        sys.exit(1)

    event_id = event_ids[0]

    # Find Karen Lee's partner ID
    karen_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                  [[['name', '=', 'Karen Lee']]])
    karen_id = karen_ids[0] if karen_ids else None

    # Build write values: reset to challenge baseline
    write_vals = {
        'location': 'Zoom Meeting',      # agent must change to Board Room
        'description': False,            # agent must add agenda
        'alarm_ids': [(5, 0, 0)],        # clear all alarms; agent must add reminder
    }

    # Remove Karen Lee from attendees if present
    if karen_id:
        write_vals['partner_ids'] = [(3, karen_id)]

    models.execute_kw(db, uid, 'admin', 'calendar.event', 'write',
                      [[event_id], write_vals])
    print(event_id)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

echo "Investor Update Preparation event_id=$EVENT_ID (reset to challenge baseline)"

# Record baseline AFTER reset so counts reflect clean starting state (Anti-pattern 3)
record_task_baseline "investor_meeting_update"

# Open Firefox directly to the event form so the agent sees the target meeting
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$EVENT_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$EVENT_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/investor_meeting_start.png

echo "Task start state: 'Investor Update Preparation' event form is open."
echo "Agent must: add Legal Counsel, set location to Board Room, add description, add reminder."
echo "=== investor_meeting_update task setup complete ==="
