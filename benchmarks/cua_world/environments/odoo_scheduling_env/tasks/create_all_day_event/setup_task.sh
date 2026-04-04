#!/bin/bash
echo "=== Setting up create_all_day_event task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "create_all_day_event"

# Remove any existing 'Company Offsite Day' events to keep task fresh
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Company Offsite Day']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Removed existing 'Company Offsite Day' event(s)")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

NEXT_FRIDAY=$(python3 -c "
from datetime import date, timedelta
today = date.today()
days_until_friday = (4 - today.weekday()) % 7
if days_until_friday == 0:
    days_until_friday = 7
print((today + timedelta(days=days_until_friday)).strftime('%A, %B %d, %Y'))
")

echo "Next Friday: $NEXT_FRIDAY"

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Odoo Calendar is shown."
echo "Agent should create an all-day event 'Company Offsite Day' on next Friday ($NEXT_FRIDAY)."
echo "=== create_all_day_event task setup complete ==="
