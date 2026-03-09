#!/bin/bash
echo "=== Setting up create_meeting task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "create_meeting"

# Remove any existing 'Q3 Business Review' events to keep task fresh
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Q3 Business Review']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Removed existing 'Q3 Business Review' event(s)")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Compute next Monday's date for the task description context
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

# Navigate Firefox to the Calendar view
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Odoo Calendar view is shown."
echo "Agent should create 'Q3 Business Review' meeting on next Monday ($NEXT_MONDAY) at 2:00 PM."
echo "=== create_meeting task setup complete ==="
