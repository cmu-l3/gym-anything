#!/bin/bash
set -e
echo "=== Setting up invite_managers_to_meeting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset the specific event to a known initial state
# - Event: "Q2 Financial Review"
# - Attendees: Alice Johnson, Bob Williams, Henry Kim
# - Ensure Manager contacts exist
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
import time

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Get IDs for original attendees
    original_names = ['Alice Johnson', 'Bob Williams', 'Henry Kim']
    original_ids = []
    for name in original_names:
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        if ids:
            original_ids.append(ids[0])
        else:
            print(f"Warning: Original attendee {name} not found!", file=sys.stderr)

    # 2. Get IDs for managers (to ensure they exist for the task)
    manager_names = ['Carol Martinez', 'Emma Thompson', 'Isabel Santos']
    for name in manager_names:
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        if not ids:
             print(f"Warning: Manager {name} not found! Data setup might be incomplete.", file=sys.stderr)

    # 3. Find and reset the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                               [[['name', '=', 'Q2 Financial Review']]])
    
    if events:
        event_id = events[0]
        # Reset attendees to only original ones
        # Command (6, 0, [ids]) replaces all existing links with the new list
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
                          [[event_id], {'partner_ids': [(6, 0, original_ids)]}])
        print(f"Reset 'Q2 Financial Review' (id={event_id}) attendees to: {original_names}")
    else:
        print("Error: 'Q2 Financial Review' event not found!", file=sys.stderr)
        sys.exit(1)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is running and logged in
# We start at the main menu so the agent has to navigate to Contacts/Calendar
ensure_firefox "http://localhost:8069/web"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="