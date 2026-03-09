#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Lost Reasons task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running
wait_for_odoo

# Clean up target reasons if they already exist (idempotency)
echo "Cleaning up any pre-existing target reasons..."
python3 - <<'PYEOF'
import xmlrpc.client
import sys

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    target_reasons = [
        "Chose a Competitor",
        "Project Cancelled", 
        "Project Canceled",
        "Decision Maker Left Company"
    ]

    # Find existing records matching our targets (case insensitive ilike)
    for reason in target_reasons:
        ids = models.execute_kw('odoodb', uid, 'admin', 'crm.lost.reason', 'search',
            [[['name', 'ilike', reason]]])
        
        if ids:
            print(f"Removing pre-existing reason '{reason}' (IDs: {ids})")
            models.execute_kw('odoodb', uid, 'admin', 'crm.lost.reason', 'unlink', [ids])
        else:
            print(f"Reason '{reason}' not found (clean)")

except Exception as e:
    print(f"Error during cleanup: {e}")
    sys.exit(1)
PYEOF

# Record initial count of lost reasons
INITIAL_COUNT=$(odoo_db_query "SELECT COUNT(*) FROM crm_lost_reason;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial lost reasons count: $INITIAL_COUNT"

# Ensure Firefox is running and logged in
# We start at the main Pipeline view, forcing the user to navigate to Configuration
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="