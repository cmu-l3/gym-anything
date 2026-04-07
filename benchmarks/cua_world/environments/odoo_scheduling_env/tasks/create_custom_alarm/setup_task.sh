#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_custom_alarm task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean state: Remove any existing 3-hour alarms and clear alarms from target event
# This forces the agent to actually perform the creation steps
python3 << 'PYEOF'
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

    # 1. Find and delete any global alarms that match 3 hours (to force creation)
    # We check for "3 Hours" and "180 Minutes"
    existing_alarms = models.execute_kw(db, uid, password, 'calendar.alarm', 'search',
        ['|', '&', ('duration', '=', 3), ('interval', '=', 'hours'), 
              '&', ('duration', '=', 180), ('interval', '=', 'minutes')])
    
    if existing_alarms:
        print(f"Removing {len(existing_alarms)} pre-existing 3-hour alarms to force creation...")
        models.execute_kw(db, uid, password, 'calendar.alarm', 'unlink', [existing_alarms])

    # 2. Clear alarms from the specific event "Q2 Financial Review"
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Q2 Financial Review']]])
    
    if events:
        # Command 5: Unlink all (remove all M2M associations)
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
            [events, {'alarm_ids': [[5]]}]) 
        print(f"Cleared alarms from 'Q2 Financial Review' (ID: {events[0]})")
    else:
        print("WARNING: 'Q2 Financial Review' event not found!", file=sys.stderr)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and navigated to Calendar
# This function handles the "First Run" logic and snap lock clearing
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="