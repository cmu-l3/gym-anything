#!/bin/bash
set -e
echo "=== Setting up replicate_training_schedule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
# Also in ISO format for Python comparisons if needed
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_iso.txt

# --------------------------------------------------------------------------
# Inject the initial Monday events via Python XML-RPC
# --------------------------------------------------------------------------
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Calculate Monday of Week 3 (Next Monday + 14 days)
    # This ensures it's always in the future and consistent
    today = datetime.now()
    days_to_monday = (7 - today.weekday()) % 7
    if days_to_monday == 0:
        days_to_monday = 7
    next_monday = today + timedelta(days=days_to_monday)
    target_monday = next_monday + timedelta(days=14)
    target_tuesday = target_monday + timedelta(days=1)
    
    # Format dates for Odoo (UTC)
    # We set times assuming the system is using UTC for simplicity in this env
    mon_str = target_monday.strftime('%Y-%m-%d')
    tue_str = target_tuesday.strftime('%Y-%m-%d')
    
    print(f"Target Monday: {mon_str}")
    print(f"Target Tuesday: {tue_str}")

    # 1. Clean up any existing "Security Workshop" events on these days to ensure clean state
    # We search for any event with 'Security Workshop' in the name
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'ilike', 'Security Workshop']]])
    
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing Security Workshop events.")

    # 2. Create the 3 events on Monday
    # Events: 
    #   Phishing: 09:00 - 10:30
    #   Data Protection: 11:00 - 12:30
    #   Incident Response: 13:30 - 15:00
    
    events_to_create = [
        {
            'name': 'Security Workshop: Phishing',
            'start': f"{mon_str} 09:00:00",
            'stop': f"{mon_str} 10:30:00",
            'location': 'Training Room B',
            'description': 'Learn how to identify and report phishing attempts.',
            'duration': 1.5
        },
        {
            'name': 'Security Workshop: Data Protection',
            'start': f"{mon_str} 11:00:00",
            'stop': f"{mon_str} 12:30:00",
            'location': 'Training Room B',
            'description': 'Best practices for handling sensitive company data.',
            'duration': 1.5
        },
        {
            'name': 'Security Workshop: Incident Response',
            'start': f"{mon_str} 13:30:00",
            'stop': f"{mon_str} 15:00:00",
            'location': 'Training Room B',
            'description': 'Steps to take immediately after a security breach.',
            'duration': 1.5
        }
    ]

    for evt in events_to_create:
        eid = models.execute_kw(db, uid, password, 'calendar.event', 'create', [evt])
        print(f"Created event {evt['name']} (ID: {eid})")

    # Save dates to a temp file for the verifier/export script to know what dates to check
    with open('/tmp/target_dates.txt', 'w') as f:
        f.write(f"{mon_str},{tue_str}")

except Exception as e:
    print(f"Error in setup: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# --------------------------------------------------------------------------
# Setup Application State
# --------------------------------------------------------------------------

# Ensure Firefox is running and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Wait a moment for page load
sleep 5

# We want to try to navigate the calendar to the target week so the agent sees the events immediately.
# However, manipulating the JS calendar via URL is tricky. 
# We'll just leave it at the default view (current week/month) and let the agent navigate.
# The task description gives explicit instructions ("Monday of Week 3").

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="