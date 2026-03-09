#!/bin/bash
echo "=== Setting up reschedule_meeting task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "reschedule_meeting"

# Create a fresh 'Tax Advisory - Alice Johnson' meeting 3 days from now at 10 AM
MEETING_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
from datetime import datetime, timedelta
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get Alice Johnson's partner ID
    partner_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                    [[['name', '=', 'Alice Johnson']]])
    partner_id = partner_ids[0] if partner_ids else None

    # Remove any existing Tax Advisory meetings for Alice Johnson
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Tax Advisory - Alice Johnson']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])

    # Create a fresh meeting 3 days from now at 10:00 AM
    start = (datetime.now().replace(hour=10, minute=0, second=0, microsecond=0)
             + timedelta(days=3))
    stop = start + timedelta(hours=1)

    event_data = {
        'name': 'Tax Advisory - Alice Johnson',
        'start': start.strftime('%Y-%m-%d %H:%M:%S'),
        'stop': stop.strftime('%Y-%m-%d %H:%M:%S'),
    }
    if partner_id:
        event_data['partner_ids'] = [(4, partner_id)]

    event_id = models.execute_kw(db, uid, 'admin', 'calendar.event', 'create', [event_data])
    print(event_id)
except Exception as e:
    print('', file=sys.stdout)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
)

echo "Created 'Tax Advisory - Alice Johnson' meeting (event_id=$MEETING_ID)"
echo "$MEETING_ID" > /tmp/reschedule_meeting_id.txt

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$MEETING_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$MEETING_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/task_start.png

ORIGINAL_DATE=$(python3 -c "
from datetime import datetime, timedelta
start = datetime.now().replace(hour=10, minute=0, second=0, microsecond=0) + timedelta(days=3)
print(start.strftime('%A, %B %d, %Y at 10:00 AM'))
")
RESCHEDULED_DATE=$(python3 -c "
from datetime import datetime, timedelta
start = datetime.now().replace(hour=10, minute=0, second=0, microsecond=0) + timedelta(days=10)
print(start.strftime('%A, %B %d, %Y at 10:00 AM'))
")

echo "Task start state: 'Tax Advisory - Alice Johnson' meeting is shown."
echo "Original date: $ORIGINAL_DATE"
echo "Agent should reschedule to: $RESCHEDULED_DATE (1 week later)"
echo "=== reschedule_meeting task setup complete ==="
