#!/bin/bash
set -e
echo "=== Setting up schedule_meeting_with_new_contact task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox first to ensure environment is ready
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Clean up previous runs and establish baseline
# We use a Python script to interact with Odoo via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys
import json

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Clean up existing 'Patricia Nguyen' contacts
    contacts = models.execute_kw(db, uid, password, 'res.partner', 'search',
                                [[['name', '=', 'Patricia Nguyen']]])
    if contacts:
        models.execute_kw(db, uid, password, 'res.partner', 'unlink', [contacts])
        print(f"Cleaned up {len(contacts)} existing contact(s).")

    # 2. Clean up existing 'Onboarding Call' events
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                              [[['name', 'ilike', 'Onboarding Call - Westfield']]])
    if events:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [events])
        print(f"Cleaned up {len(events)} existing event(s).")
    
    # 3. Get Max IDs (for anti-gaming: check if new records are created)
    # Get all IDs and find max, or 0 if empty
    all_partner_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[]])
    max_partner_id = max(all_partner_ids) if all_partner_ids else 0
    
    all_event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[]])
    max_event_id = max(all_event_ids) if all_event_ids else 0

    baseline = {
        "max_partner_id": max_partner_id,
        "max_event_id": max_event_id,
        "partner_count": len(all_partner_ids),
        "event_count": len(all_event_ids)
    }

    with open('/tmp/task_baseline.json', 'w') as f:
        json.dump(baseline, f)
        
    print(f"Baseline established: Max Partner ID={max_partner_id}, Max Event ID={max_event_id}")

except Exception as e:
    print(f"Setup error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is focused and maximized at the start
focus_window "Firefox"
sleep 1
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="