#!/bin/bash
echo "=== Setting up set_event_privacy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use Python to set up the specific event state
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

def get_odoo_connection():
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        return uid, models
    except Exception as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        return None, None

uid, models = get_odoo_connection()
if not uid:
    sys.exit(1)

# Target event
target_name = "Investor Update Preparation"

# Search for the event
event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
    [[['name', '=', target_name]]])

if not event_ids:
    print(f"ERROR: Event '{target_name}' not found. Creating it now.", file=sys.stderr)
    # Fallback: create it if missing (should exist from global setup, but being safe)
    # Calculate a date 2 weeks from now
    from datetime import datetime, timedelta
    start_dt = datetime.now().replace(hour=11, minute=0, second=0) + timedelta(days=14)
    stop_dt = start_dt + timedelta(hours=1.5)
    
    event_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': target_name,
        'start': start_dt.strftime('%Y-%m-%d %H:%M:%S'),
        'stop': stop_dt.strftime('%Y-%m-%d %H:%M:%S'),
        'location': 'Board Room',
        'description': 'Prepare Q2 investor update materials and talking points.',
        'privacy': 'public',
        'show_as': 'busy'
    }])
    event_ids = [event_id]

event_id = event_ids[0]

# RESET STATE: Ensure it starts as Public (Everyone) and Busy
# privacy: public=Everyone, private=Private, confidential=Only Internal Users
# show_as: busy=Busy, free=Free
models.execute_kw(db, uid, password, 'calendar.event', 'write',
    [[event_id], {
        'privacy': 'public',
        'show_as': 'busy'
    }])

# Read back state to confirm and record baseline
event = models.execute_kw(db, uid, password, 'calendar.event', 'read',
    [event_id], 
    {'fields': ['id', 'name', 'privacy', 'show_as', 'write_date', 'start', 'stop']})[0]

baseline = {
    'event_id': event['id'],
    'initial_privacy': event['privacy'],
    'initial_show_as': event['show_as'],
    'initial_write_date': event['write_date'],
    'initial_name': event['name'],
    'initial_start': event['start'],
    'initial_stop': event['stop']
}

with open('/tmp/task_baseline.json', 'w') as f:
    json.dump(baseline, f, indent=2)

print(f"Setup complete for event {event_id}: privacy={event['privacy']}, show_as={event['show_as']}")
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# We use month view as the event is likely in the future
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=month"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="