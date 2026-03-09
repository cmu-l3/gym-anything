#!/bin/bash
echo "=== Setting up create_recurring_event task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "create_recurring_event"

# Remove any existing 'Weekly Team Standup' events
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Weekly Team Standup']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Removed {len(existing)} existing 'Weekly Team Standup' event(s)")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

NEXT_MONDAY=$(python3 -c "
from datetime import date, timedelta
today = date.today()
days_until_monday = (7 - today.weekday()) % 7
if days_until_monday == 0:
    days_until_monday = 7
next_monday = today + timedelta(days=days_until_monday)
print(next_monday.strftime('%A, %B %d, %Y'))
")

echo "Next Monday: $NEXT_MONDAY"

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Odoo Calendar view is shown."
echo "Agent should create 'Weekly Team Standup' as a recurring weekly event starting next Monday ($NEXT_MONDAY) at 9:00 AM."
echo "=== create_recurring_event task setup complete ==="
