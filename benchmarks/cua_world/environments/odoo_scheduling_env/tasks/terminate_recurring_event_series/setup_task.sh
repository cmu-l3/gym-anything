#!/bin/bash
echo "=== Setting up terminate_recurring_event_series task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate dates using Python for precision
# Target: Next Friday (or this Friday if today is Friday)
# Start: 4 weeks ago
eval $(python3 -c "
from datetime import datetime, timedelta
now = datetime.now()
# Find next Friday (weekday 4)
days_ahead = (4 - now.weekday() + 7) % 7
if days_ahead == 0:
    days_ahead = 7
target_friday = now + timedelta(days=days_ahead)
# Start 4 weeks before that
start_date = target_friday - timedelta(weeks=4)

print(f'TARGET_DATE=\"{target_friday.strftime(\"%Y-%m-%d\")}\"')
print(f'TARGET_DATE_FULL=\"{target_friday.strftime(\"%A, %B %d, %Y\")}\"')
print(f'START_DATE=\"{start_date.strftime(\"%Y-%m-%d\")}\"')
")

echo "Target End Date: $TARGET_DATE ($TARGET_DATE_FULL)"
echo "Series Start Date: $START_DATE"

# Save target date for export script
echo "$TARGET_DATE" > /tmp/target_date.txt

# Create the recurring event via Odoo RPC
python3 << PYTHON_EOF
import xmlrpc.client, sys, time
from datetime import datetime

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Clean up any existing 'Project Phoenix Standup' events
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Project Phoenix Standup']]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing events.")

    # 2. Create the recurring event
    # Note: Odoo 17 handles recurrence via 'recurrency': True and specific fields
    # We set it to repeat weekly on Fridays, forever (no 'count' or 'until')
    
    event_vals = {
        'name': 'Project Phoenix Standup',
        'start': '$START_DATE 09:00:00',
        'stop': '$START_DATE 09:30:00',
        'duration': 0.5,
        'recurrency': True,
        'rrule_type': 'weekly',
        'tue': False, 'wed': False, 'thu': False, 'mon': False, 'sat': False, 'sun': False,
        'fri': True,  # Repeat on Fridays
        'interval': 1,
        'end_type': 'forever', # Infinite recurrence
        'description': 'Weekly sync for Project Phoenix status updates.',
        'location': 'Meeting Room 1'
    }

    event_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [event_vals])
    print(f"Created recurring event series (id={event_id}) starting $START_DATE")

except Exception as e:
    print(f"Error creating event: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Record initial state for anti-gaming
record_task_baseline "terminate_recurring_event_series"

# Ensure Firefox is running and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Navigate to Calendar view
# We might need to navigate to the specific date if it's far in the future/past,
# but usually Odoo opens near "today". Since the target is "next Friday", it should be close.
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Friday: $TARGET_DATE_FULL"