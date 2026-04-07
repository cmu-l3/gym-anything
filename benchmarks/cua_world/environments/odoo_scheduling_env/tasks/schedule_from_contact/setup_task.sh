#!/bin/bash
echo "=== Setting up schedule_from_contact task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial event count
INITIAL_COUNT=$(count_calendar_events)
echo "$INITIAL_COUNT" > /tmp/initial_event_count.txt

# Cleanup: Remove any existing event with the target name to ensure fresh creation
python3 << 'EOF'
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
    
    # Search for existing task events
    ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Q2 Performance Debrief with CFO']]])
    
    if ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [ids])
        print(f"Cleaned up {len(ids)} existing event(s).")
except Exception as e:
    print(f"Cleanup warning: {e}", file=sys.stderr)
EOF

# Calculate "Next Thursday" for logging/debug context (Agent figures this out from system date)
NEXT_THURSDAY=$(python3 -c "
from datetime import date, timedelta
today = date.today()
# weekday: Mon=0, Thu=3. 
days_ahead = (3 - today.weekday() + 7) % 7
if days_ahead == 0:
    days_ahead = 7
target = today + timedelta(days=days_ahead)
print(target.strftime('%Y-%m-%d'))
")
echo "Target Date (Next Thursday): $NEXT_THURSDAY"

# Launch Firefox and start at the Calendar view (as per Starting State description)
# This forces the agent to explicitly navigate to Contacts module
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="