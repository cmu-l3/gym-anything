#!/bin/bash
set -e
echo "=== Setting up convert_event_to_allday task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Reset the specific event to ensure it is NOT all-day initially
echo "Resetting event state..."
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, datetime
url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', 'ilike', 'Legal Contract Review']]],
        {'fields': ['id', 'name', 'start', 'allday']})

    if events:
        event = events[0]
        # Reset to timed event if it was somehow all-day
        # We need to ensure it has a time component. 
        # For simplicity, we just set allday=False. 
        # Ideally we'd reset the time too, but preserving existing start/stop is usually fine
        # as long as we force allday=False.
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
            [[event['id']], {'allday': False}])
        print(f"Reset event {event['id']} to allday=False")
        
        # Record baseline for verifier
        with open('/tmp/task_baseline.json', 'w') as f:
            import json
            json.dump({
                'event_id': event['id'], 
                'initial_allday': False,
                'initial_start': event['start']
            }, f)
    else:
        print("ERROR: Event 'Legal Contract Review' not found!", file=sys.stderr)
        sys.exit(1)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# We use the ensure_firefox utility which handles session cleaning and login
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="