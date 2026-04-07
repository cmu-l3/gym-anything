#!/bin/bash
set -e
echo "=== Setting up finalize_tentative_schedule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running
# (The environment usually has it running, but we ensure functionality)

# Python script to inject the specific "Hold" events and save their IDs
# We perform this via XML-RPC to simulate "pre-existing" data
python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # Clean up any existing "Hold: Q3 Budget Review" or "Q3 Budget Review" events
    # to ensure a clean slate and no confusion
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'ilike', 'Q3 Budget Review']]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing events.")

    # Calculate dates for "Next Week"
    # Logic: Find next Monday
    now = datetime.datetime.now().replace(second=0, microsecond=0)
    days_to_monday = (7 - now.weekday()) % 7 or 7
    next_monday = now + datetime.timedelta(days=days_to_monday)
    
    # Times: Tue 10:00, Wed 14:00, Thu 11:00
    # Note: Odoo stores times in UTC. 
    # If the Odoo instance is set to a specific timezone, this might need adjustment.
    # However, the standard Odoo docker setup usually defaults to UTC or respects the input string as-is for simple setups.
    # We will assume the agent sees what we set here.
    
    tue_start = (next_monday + datetime.timedelta(days=1)).replace(hour=10, minute=0)
    wed_start = (next_monday + datetime.timedelta(days=2)).replace(hour=14, minute=0)
    thu_start = (next_monday + datetime.timedelta(days=3)).replace(hour=11, minute=0)

    def create_hold(dt, name="Hold: Q3 Budget Review"):
        # Create 1-hour event
        stop_dt = dt + datetime.timedelta(hours=1)
        return models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
            'name': name,
            'start': dt.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': stop_dt.strftime('%Y-%m-%d %H:%M:%S'),
            'description': 'Tentative hold for budget review.',
            'location': 'Board Room'
        }])

    print("Creating tentative events...")
    id_tue = create_hold(tue_start)
    id_wed = create_hold(wed_start)
    id_thu = create_hold(thu_start)
    
    print(f"Created IDs: Tue={id_tue}, Wed={id_wed}, Thu={id_thu}")

    # Save IDs for verification later
    # We save this to a file that export_result.sh can read
    with open('/tmp/task_event_ids.json', 'w') as f:
        json.dump({
            'tue_id': id_tue, 
            'wed_id': id_wed, 
            'thu_id': id_thu,
            'wed_expected_start': wed_start.strftime('%Y-%m-%d %H:%M:%S')
        }, f)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is running and navigate to Calendar
# We point to the calendar action to ensure the view is loaded
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="