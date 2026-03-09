#!/bin/bash
echo "=== Setting up schedule_recurring_standup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_iso.txt

# Wait for Odoo to be ready
wait_for_odoo

# Clean up any existing events with the target name to ensure a fresh start
echo "Cleaning up existing events..."
python3 - <<'PYEOF'
import xmlrpc.client
import sys

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Find existing events
    events = models.execute_kw('odoodb', uid, 'admin', 'calendar.event', 'search',
        [[['name', '=', 'Weekly Sales Standup']]])
    
    if events:
        models.execute_kw('odoodb', uid, 'admin', 'calendar.event', 'unlink', [events])
        print(f"Removed {len(events)} existing events")
    else:
        print("No existing events found")
        
except Exception as e:
    print(f"Error during cleanup: {e}", file=sys.stderr)
PYEOF

# Ensure Firefox is running and logged in
# We start at the main menu or CRM pipeline to force navigation to Calendar
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 3

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="