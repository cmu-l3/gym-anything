#!/bin/bash
set -e
echo "=== Setting up Task: Tag Strategic Accounts ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Odoo to be ready
wait_for_odoo

# 2. Setup Data via Python XML-RPC
# - Ensure 'Strategic Account' tag exists
# - Create/Reset Partners (Customers) and clear their tags
# - Create/Reset Opportunities with specific values
python3 - <<'PYEOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, username, password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

if not uid:
    print("Authentication failed")
    sys.exit(1)

# --- 1. Setup Tag ---
tag_name = "Strategic Account"
tag_ids = models.execute_kw(db, uid, password, 'res.partner.category', 'search', [[['name', '=', tag_name]]])
if not tag_ids:
    tag_id = models.execute_kw(db, uid, password, 'res.partner.category', 'create', [{'name': tag_name}])
    print(f"Created tag '{tag_name}' ID: {tag_id}")
else:
    tag_id = tag_ids[0]
    print(f"Found tag '{tag_name}' ID: {tag_id}")

# --- 2. Setup Partners and Opportunities ---
data_setup = [
    {"partner": "Logistics Pro Inc", "opp": "Global Logistics Overhaul", "revenue": 150000, "email": "contact@logipro.com"},
    {"partner": "NorthWest Retail", "opp": "Regional Expansion", "revenue": 95000, "email": "info@nwretail.com"},
    {"partner": "SmallTime LLC", "opp": "Office Supplies", "revenue": 12000, "email": "admin@smalltime.com"}
]

for item in data_setup:
    # A. Setup Partner
    partner_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', item['partner']]]])
    
    if partner_ids:
        pid = partner_ids[0]
        # Clear tags to ensure clean state
        models.execute_kw(db, uid, password, 'res.partner', 'write', [pid, {'category_id': [[6, 0, []]]}]) 
        print(f"Reset partner '{item['partner']}' (ID: {pid}) - Tags cleared")
    else:
        pid = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
            'name': item['partner'],
            'email': item['email'],
            'is_company': True
        }])
        print(f"Created partner '{item['partner']}' (ID: {pid})")

    # B. Setup Opportunity
    opp_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', item['opp']]]])
    
    opp_data = {
        'name': item['opp'],
        'partner_id': pid,
        'expected_revenue': item['revenue'],
        'type': 'opportunity',
        'probability': 20
    }
    
    if opp_ids:
        models.execute_kw(db, uid, password, 'crm.lead', 'write', [opp_ids[0], opp_data])
        print(f"Updated opportunity '{item['opp']}'")
    else:
        models.execute_kw(db, uid, password, 'crm.lead', 'create', [opp_data])
        print(f"Created opportunity '{item['opp']}'")

print("Data setup complete.")
PYEOF

# 3. Record Task Start Time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 4. Prepare Environment
# Ensure Firefox is open and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="