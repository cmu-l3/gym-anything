#!/bin/bash
echo "=== Setting up calculate_weekly_meeting_load task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any previous output file to ensure fresh creation
rm -f /home/ga/alice_load.txt

# Ensure Firefox is open and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Verify the anchor event exists (sanity check)
# We don't need to do anything if it's missing, the task will just fail, 
# but it's good for debugging logs.
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                            [[['name', '=', 'Q2 Financial Review']]])
    if ids:
        print(f"Anchor event 'Q2 Financial Review' found (ID: {ids[0]})")
    else:
        print("WARNING: Anchor event 'Q2 Financial Review' NOT found!", file=sys.stderr)
except Exception as e:
    print(f"Error checking anchor event: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Calendar view
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="