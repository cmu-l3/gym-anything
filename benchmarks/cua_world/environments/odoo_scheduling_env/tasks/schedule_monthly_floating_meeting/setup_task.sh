#!/bin/bash
echo "=== Setting up schedule_monthly_floating_meeting task ==="

# Source utilities (provides Odoo connection vars and helper functions)
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous runs: Remove any existing 'Department All-Hands' events
echo "Cleaning up existing events..."
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Find events
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                               [[['name', '=', 'Department All-Hands']]])
    if events:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [events])
        print(f"Removed {len(events)} existing event(s).")
    
    # Find recurrences (orphan recurrences might remain if events deleted weirdly)
    recurrences = models.execute_kw(db, uid, password, 'calendar.recurrence', 'search',
                                    [[['name', 'ilike', 'Department All-Hands']]])
    if recurrences:
        models.execute_kw(db, uid, password, 'calendar.recurrence', 'unlink', [recurrences])
        print(f"Removed {len(recurrences)} existing recurrence(s).")

except Exception as e:
    print(f"Cleanup warning: {e}", file=sys.stderr)
PYTHON_EOF

# 2. Launch Firefox and navigate to Calendar
echo "Launching Firefox..."
# ensure_firefox handles logic to attach to existing process or start new one
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="