#!/bin/bash
set -e
echo "=== Setting up update_recurring_event_series task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specific recurring event for this task using Python
# We delete any existing ones first to ensure a clean state
python3 << 'PYEOF'
import xmlrpc.client
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
password = 'admin'
username = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Clean up existing events with this name
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Weekly Operations Sync']]])
    
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing events.")

    # 2. Calculate next Monday 09:00
    now = datetime.now()
    days_ahead = (7 - now.weekday()) % 7
    if days_ahead == 0: days_ahead = 7
    next_monday = (now + timedelta(days=days_ahead)).replace(hour=9, minute=0, second=0, microsecond=0)
    
    start_str = next_monday.strftime('%Y-%m-%d %H:%M:%S')
    stop_str = (next_monday + timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S')

    # 3. Create recurring event
    # rrule_type: weekly
    # count: 10 occurrences
    eid = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Weekly Operations Sync',
        'start': start_str,
        'stop': stop_str,
        'location': 'Room 3A',
        'description': 'Coordination for ops team.',
        'recurrency': True,
        'rrule_type': 'weekly',
        'interval': 1,
        'count': 10,
        'privacy': 'public',
        'show_as': 'busy'
    }])
    
    print(f"Created recurring event id={eid} at {start_str}")

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is open and on the calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="