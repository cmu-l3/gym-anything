#!/bin/bash
echo "=== Setting up duplicate_and_modify_event task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial event count for anti-gaming
INITIAL_COUNT=$(count_calendar_events)
echo "$INITIAL_COUNT" > /tmp/initial_event_count.txt
echo "Initial event count: $INITIAL_COUNT"

# Record Q2 event baseline (to verify preservation later)
# We save this to a file that the export script can also read or compare against
python3 << 'PYEOF'
import xmlrpc.client, json, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Find Q2 event
    q2 = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read',
        [[['name', '=', 'Q2 Financial Review']]],
        {'fields': ['id', 'name', 'start', 'stop', 'location', 'description', 'partner_ids', 'write_date'], 'limit': 1})
    
    if q2:
        with open('/tmp/q2_baseline.json', 'w') as f:
            json.dump(q2[0], f)
        print(f"Q2 baseline recorded: {q2[0]['name']}")
    else:
        print("ERROR: Q2 Financial Review event not found during setup!")
        sys.exit(1)
except Exception as e:
    print(f"Error recording baseline: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and navigated to the Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

# Wait for render
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="