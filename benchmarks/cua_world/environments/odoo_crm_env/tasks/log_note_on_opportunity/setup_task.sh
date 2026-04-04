#!/bin/bash
set -e
echo "=== Setting up log_note_on_opportunity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running
wait_for_odoo

# Python script to seed the specific opportunity and record state
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # 1. Create/Find Partner
    partner_name = "Gemini Furniture"
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', partner_name]]])
    if partners:
        partner_id = partners[0]
    else:
        partner_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
            'name': partner_name,
            'is_company': True,
            'email': 'info@geminifurniture.example.com'
        }])

    # 2. Create/Find Opportunity
    opp_name = "Warehouse Renovation - Gemini Furniture"
    leads = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', opp_name]]])
    
    if leads:
        lead_id = leads[0]
        # Reset description and other fields to ensure clean state
        models.execute_kw(db, uid, password, 'crm.lead', 'write', [[lead_id], {
            'description': False,
            'partner_id': partner_id,
            'expected_revenue': 45000,
        }])
        print(f"Reset existing opportunity ID: {lead_id}")
    else:
        lead_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
            'name': opp_name,
            'partner_id': partner_id,
            'type': 'opportunity',
            'expected_revenue': 45000,
            'description': 'Inquiry about warehouse renovation.',
            'priority': '2'
        }])
        print(f"Created new opportunity ID: {lead_id}")

    # 3. Save Lead ID for export script
    with open('/tmp/target_lead_id.txt', 'w') as f:
        f.write(str(lead_id))

    # 4. Record initial message count
    msg_count = models.execute_kw(db, uid, password, 'mail.message', 'search_count', 
        [[['res_model', '=', 'crm.lead'], ['res_id', '=', lead_id]]])
    
    with open('/tmp/initial_msg_count.txt', 'w') as f:
        f.write(str(msg_count))
        
    print(f"Initial message count: {msg_count}")

except Exception as e:
    print(f"Error in setup: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in, showing the Pipeline
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 2

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="