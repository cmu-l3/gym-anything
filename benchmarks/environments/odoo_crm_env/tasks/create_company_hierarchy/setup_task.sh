#!/bin/bash
set -e
echo "=== Setting up create_company_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Clean up any existing test records to ensure a fresh start
echo "Cleaning up any existing records..."
python3 - <<'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, passwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    names_to_clean = [
        "Elena Rossi",
        "Kenji Tanaka",
        "Nexus Global - Europe",
        "Nexus Global - Asia Pacific",
        "Nexus Global Industries",
    ]

    for name in names_to_clean:
        ids = models.execute_kw(db, uid, passwd, 'res.partner', 'search', [[['name', '=', name]]])
        if ids:
            # Handle potential parent/child constraint issues by unlinking children first if necessary
            # or just rely on cascade delete if configured (Odoo usually blocks)
            # We'll just try to unlink.
            try:
                models.execute_kw(db, uid, passwd, 'res.partner', 'unlink', [ids])
                print(f"Cleaned: {name}")
            except Exception as e:
                print(f"Could not immediately unlink {name}, trying to clear parents first...")
                models.execute_kw(db, uid, passwd, 'res.partner', 'write', [ids, {'parent_id': False}])
                models.execute_kw(db, uid, passwd, 'res.partner', 'unlink', [ids])
except Exception as e:
    print(f"Setup warning: {e}")
PYEOF

# Record initial partner count
INITIAL_COUNT=$(odoo_db_query "SELECT COUNT(*) FROM res_partner;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_partner_count.txt

# Ensure Firefox is running and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=contacts.action_contacts&cids=1&menu_id=117"
sleep 5

# Maximize Firefox window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="