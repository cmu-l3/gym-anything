#!/bin/bash
echo "=== Setting up book_meeting task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "book_meeting"

# Remove any prior 'Career Coaching Session - Emma Thompson' meetings and get Emma's contact ID
EMMA_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Remove prior meetings
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Career Coaching Session - Emma Thompson']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Removed {len(existing)} prior meeting(s)", file=sys.stderr)

    # Get Emma Thompson's partner ID
    emma = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                             [[['name', '=', 'Emma Thompson']]])
    print(emma[0] if emma else '')
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
    print('')
PYTHON_EOF
)

NEXT_WEDNESDAY=$(python3 -c "
from datetime import date, timedelta
today = date.today()
days_until_wed = (2 - today.weekday()) % 7
if days_until_wed == 0:
    days_until_wed = 7
print((today + timedelta(days=days_until_wed)).strftime('%A, %B %d, %Y'))
")

echo "Next Wednesday: $NEXT_WEDNESDAY"
echo "Emma Thompson partner_id=$EMMA_ID"

# Navigate to Emma Thompson's contact form — different starting point from create_meeting
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$EMMA_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$EMMA_ID&model=res.partner&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=contacts.action_contacts"
    sleep 3
fi

take_screenshot /tmp/task_start.png

echo "Task start state: Emma Thompson's contact page is shown."
echo "Agent should schedule a meeting with Emma from this contact page for next Wednesday ($NEXT_WEDNESDAY) at 3:00 PM."
echo "=== book_meeting task setup complete ==="
