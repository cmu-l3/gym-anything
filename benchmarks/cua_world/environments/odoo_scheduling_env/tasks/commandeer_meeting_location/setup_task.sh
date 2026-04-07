#!/bin/bash
set -e
echo "=== Setting up Commandeer Meeting Location task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate Next Monday's date for the event
# Python script to calculate date and setup Odoo state
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

def get_next_monday():
    today = datetime.now().date()
    days_ahead = 0 - today.weekday() + 7
    if days_ahead <= 0:
        days_ahead += 7
    return today + timedelta(days=days_ahead)

try:
    # Authenticate
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    next_monday = get_next_monday()
    start_time_str = f"{next_monday} 09:00:00"
    stop_time_str = f"{next_monday} 09:30:00"

    print(f"Setting up events for {next_monday}...")

    # 1. CLEANUP: Remove any existing 'External Audit Kickoff' to prevent pre-task artifacts
    audit_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'External Audit Kickoff']]])
    if audit_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [audit_ids])
        print(f"Cleaned up {len(audit_ids)} existing audit events.")

    # 2. SETUP: Ensure 'Team Standup' exists at the right time and location
    # Find existing standups on that day to update, or create new
    standup_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Team Standup'], ['start', '=', start_time_str]]])
    
    vals = {
        'name': 'Team Standup',
        'start': start_time_str,
        'stop': stop_time_str,
        'location': 'Main Conference Room',
        'description': 'Daily sync',
        # Ensure we don't have the audit attendees on the standup
        # Just put admin for simplicity or keep existing
    }

    standup_id = None
    if standup_ids:
        standup_id = standup_ids[0]
        models.execute_kw(db, uid, password, 'calendar.event', 'write', [[standup_id], vals])
        print(f"Reset existing Team Standup (id={standup_id}) to baseline.")
    else:
        standup_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [vals])
        print(f"Created new Team Standup (id={standup_id}).")
    
    # Save the ID of the standup to verify it wasn't deleted later
    with open('/tmp/standup_baseline_id.txt', 'w') as f:
        f.write(str(standup_id))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# We use the month view or week view to ensure the agent can see the upcoming Monday
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

# Wait for load
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="