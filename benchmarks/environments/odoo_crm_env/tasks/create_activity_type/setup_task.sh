#!/bin/bash
set -e
echo "=== Setting up create_activity_type task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Clean up any existing 'Product Demo' activity type to ensure a fresh start
echo "Cleaning up existing activity types..."
python3 - <<'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # Find existing records
    ids = models.execute_kw(db, uid, password, 'mail.activity.type', 'search',
        [[['name', '=', 'Product Demo']]])
    
    if ids:
        print(f"Found {len(ids)} existing records. Deleting...")
        models.execute_kw(db, uid, password, 'mail.activity.type', 'unlink', [ids])
        print("Cleanup successful.")
    else:
        print("No existing records found.")

    # Record initial count of activity types
    count = models.execute_kw(db, uid, password, 'mail.activity.type', 'search_count', [[]])
    with open('/tmp/initial_count.txt', 'w') as f:
        f.write(str(count))

except Exception as e:
    print(f"Error during setup: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in
# Start at the main CRM pipeline, NOT in developer mode
# We explicitly want the agent to enable developer mode themselves
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="