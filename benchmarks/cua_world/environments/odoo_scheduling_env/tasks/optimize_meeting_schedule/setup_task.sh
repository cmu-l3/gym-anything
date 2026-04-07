#!/bin/bash
set -e
echo "=== Setting up optimize_meeting_schedule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset specific events for this task using Python
# We need strictly controlled state:
# 1. Team Standup: Next Monday 09:00-09:30, Main Conference Room
# 2. Q2 Financial Review: Next Monday 10:00-11:30, Conference Room A (Gap of 30 mins)

python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Calculate Next Monday
    today = datetime.date.today()
    days_until_monday = (7 - today.weekday()) % 7
    if days_until_monday == 0:
        days_until_monday = 7
    next_monday = today + datetime.timedelta(days=days_until_monday)
    
    # Define time slots (assuming server is UTC or matches local display for simplicity in setup)
    # If Odoo is UTC, we set times accordingly. Standard Odoo docker is usually UTC.
    # We will set them assuming the agent sees them as 9:00.
    
    # Helper to format datetime
    def get_dt(hour, minute):
        dt = datetime.datetime.combine(next_monday, datetime.time(hour, minute))
        return dt.strftime('%Y-%m-%d %H:%M:%S')

    # Clean up existing events with these names
    event_names = ['Team Standup', 'Q2 Financial Review']
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'in', event_names]]])
    
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing events.")

    # Create Team Standup (09:00 - 09:30)
    # Using partner_ids from setup_data if available, otherwise admin
    
    # 1. Team Standup
    id1 = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Team Standup',
        'start': get_dt(9, 0),
        'stop': get_dt(9, 30),
        'location': 'Main Conference Room',
        'description': 'Daily sync.'
    }])
    print(f"Created Team Standup: {id1}")

    # 2. Q2 Financial Review (10:00 - 11:30) - 30 min gap, different room
    id2 = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Q2 Financial Review',
        'start': get_dt(10, 0),
        'stop': get_dt(11, 30),
        'location': 'Conference Room A',
        'description': 'Quarterly review.'
    }])
    print(f"Created Q2 Financial Review: {id2}")

except Exception as e:
    print(f"Error in setup: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is ready
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="