#!/bin/bash
set -e
echo "=== Setting up schedule_post_meeting_debrief task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure "Debrief" event does NOT exist (clean slate)
# and verify "Investor Update Preparation" exists
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

    # 1. Cleanup target event if exists
    debriefs = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                [[['name', '=', 'Debrief']]])
    if debriefs:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [debriefs])
        print(f"Cleaned up {len(debriefs)} existing 'Debrief' events.")

    # 2. Verify reference event exists
    refs = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                            [[['name', '=', 'Investor Update Preparation']]])
    if not refs:
        print("ERROR: Reference event 'Investor Update Preparation' not found!", file=sys.stderr)
        # In a real scenario, we might recreate it here, but the env setup should handle it.
        # We'll exit with error to fail setup if the env is broken.
        sys.exit(1)
    
    print("Setup verification successful.")

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is running and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="