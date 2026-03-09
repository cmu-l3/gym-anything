#!/bin/bash
echo "=== Setting up create_lead task ==="

source /workspace/scripts/task_utils.sh

# Wait for Odoo to be ready
wait_for_odoo

# Clean up any existing lead with the target name to ensure fresh state
python3 - <<'PYEOF'
import xmlrpc.client
common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('odoodb', 'admin', 'admin', {})
models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

target_name = 'Pacific Northwest Trading Co. - ERP Inquiry'
existing = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'search',
    [[['name', '=', target_name]]])
if existing:
    models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'unlink', [existing])
    print(f"Cleaned up {len(existing)} existing lead(s) with target name")
else:
    print("No cleanup needed")
PYEOF

# Record initial lead count for baseline comparison
python3 - > /tmp/initial_lead_count.txt <<'PYEOF'
import xmlrpc.client
common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('odoodb', 'admin', 'admin', {})
models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')
count = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'search_count', [[]])
print(count)
PYEOF
echo "Initial lead count: $(cat /tmp/initial_lead_count.txt)"

# Ensure Firefox is running and logged in, navigate to CRM new lead form
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 3

# Take screenshot to verify start state
take_screenshot /tmp/create_lead_start.png
echo "Start state screenshot saved to /tmp/create_lead_start.png"

echo "=== create_lead task setup complete ==="
