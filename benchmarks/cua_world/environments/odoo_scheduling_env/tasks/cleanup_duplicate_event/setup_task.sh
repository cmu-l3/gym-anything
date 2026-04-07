#!/bin/bash
set -e

echo "=== Setting up cleanup_duplicate_event task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the duplicate events using Python/XMLRPC
# We save the IDs to a file so we can verify the specific records later
python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import json
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Helper to find partner IDs
    def get_partner_id(name):
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        return ids[0] if ids else None

    p_alice = get_partner_id('Alice Johnson')
    p_bob = get_partner_id('Bob Williams')

    # Schedule for 3 days from now at 11:00 AM
    now = datetime.datetime.now()
    target_date = now + datetime.timedelta(days=3)
    start_time = target_date.replace(hour=11, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
    stop_time = target_date.replace(hour=12, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')

    # Create Good Event (With Attendees)
    good_vals = {
        'name': 'Vendor Evaluation',
        'start': start_time,
        'stop': stop_time,
        'partner_ids': [[6, 0, [p_alice, p_bob]]] if p_alice and p_bob else [],
        'location': 'Meeting Room 2',
        'description': 'Evaluating the new supplier proposals.'
    }
    good_event_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [good_vals])

    # Create Bad Event (No Attendees - The Duplicate)
    bad_vals = {
        'name': 'Vendor Evaluation',
        'start': start_time,
        'stop': stop_time,
        'partner_ids': [[6, 0, []]], # Empty attendees
        'location': 'Meeting Room 2',
        'description': 'Evaluating the new supplier proposals.'
    }
    bad_event_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [bad_vals])

    print(f"Setup created - Good ID: {good_event_id}, Bad ID: {bad_event_id}")

    # Save setup info for verification
    setup_info = {
        "good_event_id": good_event_id,
        "bad_event_id": bad_event_id,
        "target_date": target_date.strftime('%Y-%m-%d')
    }
    with open('/tmp/task_setup_info.json', 'w') as f:
        json.dump(setup_info, f)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and navigated to the Calendar
# We use the generic calendar action
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="