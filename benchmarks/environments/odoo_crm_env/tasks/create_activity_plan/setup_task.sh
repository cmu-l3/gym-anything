#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_activity_plan task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running
wait_for_odoo

# Use Python/XML-RPC to set up the clean state
python3 - << 'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
    
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Delete existing plan if it exists (Cleanup)
    existing_plans = models.execute_kw(db, uid, password, 'mail.activity.plan', 'search',
        [[['name', '=', 'Standard Outreach']]])
    if existing_plans:
        models.execute_kw(db, uid, password, 'mail.activity.plan', 'unlink', [existing_plans])
        print("Cleaned up existing 'Standard Outreach' plan")

    # 2. Ensure target opportunity exists
    # Check/Create Partner
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search',
        [[['name', '=', 'Acme Corp']]])
    if partners:
        partner_id = partners[0]
    else:
        partner_id = models.execute_kw(db, uid, password, 'res.partner', 'create',
            [{'name': 'Acme Corp', 'is_company': True}])

    # Check/Create Opportunity
    opps = models.execute_kw(db, uid, password, 'crm.lead', 'search',
        [[['name', '=', 'Acme Corp Inquiry']]])
    
    if opps:
        opp_id = opps[0]
        # Clear existing activities on this opp to avoid confusion
        activity_ids = models.execute_kw(db, uid, password, 'mail.activity', 'search',
            [[['res_id', '=', opp_id], ['res_model', '=', 'crm.lead']]])
        if activity_ids:
            models.execute_kw(db, uid, password, 'mail.activity', 'unlink', [activity_ids])
        print(f"Reset opportunity {opp_id} (cleared activities)")
    else:
        # Create new opportunity
        new_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
            'name': 'Acme Corp Inquiry',
            'partner_id': partner_id,
            'type': 'opportunity',
            'expected_revenue': 5000,
            'probability': 10
        }])
        print(f"Created opportunity {new_id}")

except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
PYEOF

# Record initial counts for anti-gaming
echo "0" > /tmp/initial_plan_count.txt

# Ensure Firefox is ready and logged in, start at Pipeline view
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="