#!/bin/bash
echo "=== Setting up block_travel_time task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure the environment is clean: remove any existing "Travel" events
# that might confuse the verification or the agent.
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Search for and delete any existing travel events
    travel_events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
        [[['name', 'in', ['Travel to Client', 'Return Travel']]]])
    
    if travel_events:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [travel_events])
        print(f"Cleaned up {len(travel_events)} existing travel events.")
        
    # Verify anchor event exists
    anchor = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
        [[['name', '=', 'Client Onboarding - Isabel Santos']]])
    if not anchor:
        print("WARNING: Anchor event 'Client Onboarding - Isabel Santos' not found!", file=sys.stderr)
    else:
        print("Anchor event verified present.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
PYTHON_EOF

# Ensure Firefox is open and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="