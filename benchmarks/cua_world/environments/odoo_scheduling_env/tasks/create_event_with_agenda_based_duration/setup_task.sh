#!/bin/bash
set -e
echo "=== Setting up create_event_with_agenda_based_duration task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up: Remove any existing events with the target name to ensure fresh creation
echo "Cleaning up any existing 'System Architecture Review' events..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Search for events with the specific name
    ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                            [[['name', 'ilike', 'System Architecture Review']]])
    
    if ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [ids])
        print(f"Deleted {len(ids)} existing events.")
    else:
        print("No existing events found.")

except Exception as e:
    print(f"Error during cleanup: {e}", file=sys.stderr)
PYTHON_EOF

# 3. Ensure Firefox is running and logged into Odoo Calendar
# The task requires navigating to a future date (March 13, 2026), 
# so we start at the calendar main view.
echo "Launching/Focusing Firefox..."
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# 4. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="