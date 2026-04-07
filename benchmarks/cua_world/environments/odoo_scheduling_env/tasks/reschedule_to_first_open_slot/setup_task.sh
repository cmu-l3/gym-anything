#!/bin/bash
set -e
echo "=== Setting up reschedule_to_first_open_slot task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use Python to set up the specific calendar scenario
# We need to calculate dates relative to "today" to ensure the task is always valid
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # clean up any existing events with these names to prevent duplicates/confusion
    event_names = [
        "Strategic Partnership Review", 
        "Lunch with Client", 
        "HR Quick Sync", 
        "Q3 Project Review", 
        "Email & Admin"
    ]
    domain = [['name', 'in', event_names]]
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [domain])
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing task-related events.")

    # Calculate dates
    now = datetime.now()
    # Find next Wednesday (if today is Wednesday, use next week's Wednesday to be safe/clear)
    days_ahead = (2 - now.weekday()) % 7
    if days_ahead <= 0:
        days_ahead += 7
    target_wednesday = now + timedelta(days=days_ahead)
    
    # Calculate this week's Monday (or previous Monday) for the initial position of the target event
    # We'll just put it on "Tomorrow" relative to script run if it's not Wednesday, 
    # or just fixed to next Monday if we are near the weekend.
    # Simpler: Put it on the Monday of the SAME week as the target Wednesday
    monday_of_wed_week = target_wednesday - timedelta(days=2)
    
    # Define formatting helper
    def fmt(dt, hour, minute):
        return dt.replace(hour=hour, minute=minute, second=0, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')

    # 1. Create the Target Event (initially on Monday 9am)
    target_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Strategic Partnership Review',
        'start': fmt(monday_of_wed_week, 9, 0),
        'stop': fmt(monday_of_wed_week, 10, 0), # 1 hour duration
        'description': 'Review of strategic partnership opportunities for Q3.',
        'location': 'Board Room'
    }])
    print(f"Created target event 'Strategic Partnership Review' (ID: {target_id})")

    # 2. Create Blockers on Wednesday [13:00 - 17:00]
    # Gap needed: 14:30 - 15:30
    
    # Blocker 1: 13:00 - 14:00 (Lunch)
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Lunch with Client',
        'start': fmt(target_wednesday, 13, 0),
        'stop': fmt(target_wednesday, 14, 0)
    }])
    
    # Blocker 2: 14:00 - 14:30 (HR Sync)
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'HR Quick Sync',
        'start': fmt(target_wednesday, 14, 0),
        'stop': fmt(target_wednesday, 14, 30)
    }])
    
    # TARGET SLOT IS HERE: 14:30 - 15:30 (1 hour)
    
    # Blocker 3: 15:30 - 16:30 (Q3 Review)
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Q3 Project Review',
        'start': fmt(target_wednesday, 15, 30),
        'stop': fmt(target_wednesday, 16, 30)
    }])
    
    # Blocker 4: 16:30 - 17:00 (Admin)
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Email & Admin',
        'start': fmt(target_wednesday, 16, 30),
        'stop': fmt(target_wednesday, 17, 0)
    }])

    print(f"Created blocker events on {target_wednesday.strftime('%Y-%m-%d')}")

    # Save expected solution to a temp file for the verifier/export script
    expected_start = fmt(target_wednesday, 14, 30)
    with open('/tmp/expected_solution.txt', 'w') as f:
        f.write(expected_start)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# We use the generic ensure_firefox to make sure it's running
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Try to switch to Week view if not already (Calendar usually remembers, but good to ensure)
# This is a bit tricky via URL, but the default action usually loads the last view.
# We'll just maximize and focus.
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="