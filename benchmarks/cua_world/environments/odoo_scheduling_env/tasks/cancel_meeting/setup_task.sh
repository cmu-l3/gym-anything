#!/bin/bash
echo "=== Setting up cancel_meeting task ==="

source /workspace/scripts/task_utils.sh

# Record baseline BEFORE creating the test meeting
record_task_baseline "cancel_meeting"

# Create a 'Financial Planning - Bob Williams' meeting 5 days from now at 2 PM
MEETING_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
from datetime import datetime, timedelta
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get Bob Williams' partner ID
    partner_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                    [[['name', '=', 'Bob Williams']]])
    partner_id = partner_ids[0] if partner_ids else None

    # Remove any prior 'Financial Planning - Bob Williams' meetings
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Financial Planning - Bob Williams']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])

    # Create the meeting 5 days from now at 2:00 PM
    start = (datetime.now().replace(hour=14, minute=0, second=0, microsecond=0)
             + timedelta(days=5))
    stop = start + timedelta(hours=1, minutes=30)

    event_data = {
        'name': 'Financial Planning - Bob Williams',
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

echo "Created 'Financial Planning - Bob Williams' meeting (event_id=$MEETING_ID)"
echo "$MEETING_ID" > /tmp/cancel_meeting_id.txt

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$MEETING_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$MEETING_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/task_start.png

MEETING_DATE=$(python3 -c "
from datetime import datetime, timedelta
start = datetime.now().replace(hour=14, minute=0, second=0, microsecond=0) + timedelta(days=5)
print(start.strftime('%A, %B %d, %Y at 2:00 PM'))
")

echo "Task start state: 'Financial Planning - Bob Williams' meeting is shown."
echo "Meeting date: $MEETING_DATE"
echo "Agent should delete/cancel this meeting."
echo "=== cancel_meeting task setup complete ==="
