#!/bin/bash
echo "=== Setting up Triage Sick Day Schedule task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use Python to calculate dates and setup specific scenario data
# We anchor everything to "Next Monday"
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
from datetime import datetime, timedelta, date

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

def get_next_monday():
    today = date.today()
    days_ahead = 7 - today.weekday()
    if days_ahead <= 0: # Target future Monday
        days_ahead += 7
    return today + timedelta(days=days_ahead)

try:
    # 1. Authenticate
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 2. Calculate Dates
    next_mon = get_next_monday()
    next_mon_str = next_mon.strftime('%Y-%m-%d')
    print(f"Target Date (Next Monday): {next_mon_str}")
    
    # Save target date for export script
    with open("/tmp/target_date.txt", "w") as f:
        f.write(next_mon_str)

    # 3. Get Partner IDs
    def get_pid(name):
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        if ids: return ids[0]
        # Create if not exists (fallback)
        return models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': name}])

    p_alice = get_pid("Alice Johnson")
    p_carol = get_pid("Carol Martinez")
    p_david = get_pid("David Chen")
    p_bob = get_pid("Bob Williams")
    p_henry = get_pid("Henry Kim")
    p_mentor = get_pid("Karen Lee") # Using Karen as mentor

    # 4. Clean up existing conflicting events on that day
    # We remove events with these specific names to ensure a clean slate
    event_names = ["Team Standup", "Q2 Financial Review", "One-on-One with Mentor"]
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', 
        [[['name', 'in', event_names]]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing events.")

    # 5. Create Scenarios
    
    # Event 1: Team Standup (9:00 AM, 30 min) - Alice, Carol, David
    # Action required: Remove Alice
    start_dt = f"{next_mon_str} 09:00:00"
    stop_dt = f"{next_mon_str} 09:30:00"
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Team Standup',
        'start': start_dt,
        'stop': stop_dt,
        'partner_ids': [[6, 0, [p_alice, p_carol, p_david]]],
        'description': 'Daily sync.'
    }])

    # Event 2: Q2 Financial Review (10:00 AM, 1.5 hr) - Alice, Bob, Henry
    # Action required: Reschedule to Friday
    start_dt = f"{next_mon_str} 10:00:00"
    stop_dt = f"{next_mon_str} 11:30:00"
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Q2 Financial Review',
        'start': start_dt,
        'stop': stop_dt,
        'partner_ids': [[6, 0, [p_alice, p_bob, p_henry]]],
        'location': 'Board Room'
    }])

    # Event 3: One-on-One with Mentor (2:00 PM, 1 hr) - Alice, Karen
    # Action required: Delete
    start_dt = f"{next_mon_str} 14:00:00"
    stop_dt = f"{next_mon_str} 15:00:00"
    models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'One-on-One with Mentor',
        'start': start_dt,
        'stop': stop_dt,
        'partner_ids': [[6, 0, [p_alice, p_mentor]]]
    }])

    print("Created 3 scenario events successfully.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Get the target date string for URL navigation
TARGET_DATE=$(cat /tmp/target_date.txt)

# Launch Firefox and navigate to Odoo Calendar on the target date
# Note: Odoo calendar URL uses 'start_date' parameter but usually defaults to today/week.
# We can force the view, but the agent may need to navigate. 
# To be helpful, we'll open the calendar.
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Wait a moment for load
sleep 5

# Attempt to navigate calendar view to the specific date via URL params if possible, 
# but Odoo 17 URL state is complex.
# Instead, we rely on the task description saying "Next Monday". 
# The agent needs to navigate.

take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="