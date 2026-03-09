#!/bin/bash
echo "=== Setting up create_customer task ==="

source /workspace/scripts/task_utils.sh

# Wait for Odoo to be ready
wait_for_odoo

# Clean up any existing customer with the target name
python3 - <<'PYEOF'
import xmlrpc.client

common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('odoodb', 'admin', 'admin', {})
models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

target_name = 'Meridian Financial Group'
existing = models.execute_kw('odoodb', uid, 'admin', 'res.partner', 'search',
    [[['name', '=', target_name]]])
if existing:
    models.execute_kw('odoodb', uid, 'admin', 'res.partner', 'unlink', [existing])
    print(f"Cleaned up {len(existing)} existing partner(s) with target name")
else:
    print("No cleanup needed")

# Record initial count
count = models.execute_kw('odoodb', uid, 'admin', 'res.partner', 'search_count', [[]])
print(f"Current partner count: {count}")
with open('/tmp/initial_partner_count.txt', 'w') as f:
    f.write(str(count))
PYEOF

# Navigate to Contacts module (action=154, menu_id=117)
ensure_odoo_logged_in "http://localhost:8069/web#action=154&cids=1&menu_id=117"
sleep 3

# Take screenshot to verify start state
take_screenshot /tmp/create_customer_start.png
echo "Start state screenshot saved to /tmp/create_customer_start.png"

echo "=== create_customer task setup complete ==="
