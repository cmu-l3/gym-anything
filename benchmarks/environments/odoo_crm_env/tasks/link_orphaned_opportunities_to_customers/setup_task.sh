#!/bin/bash
set -e
echo "=== Setting up Link Orphaned Opportunities task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Python script to seed data
python3 << 'PYEOF'
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
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    sys.exit(1)

# 1. Ensure Partners Exist
partners = {
    'Gemini Furniture': None,
    'Azure Interior': None,
    'Deco Addict': None
}

for p_name in partners:
    ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', p_name]]])
    if ids:
        partners[p_name] = ids[0]
        print(f"Found partner: {p_name}")
    else:
        # Create if missing
        new_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': p_name, 'is_company': True}])
        partners[p_name] = new_id
        print(f"Created partner: {p_name}")

# 2. Get 'Qualified' Stage ID
stages = models.execute_kw(db, uid, password, 'crm.stage', 'search', [[['name', '=', 'Qualified']]])
stage_id = stages[0] if stages else 1

# 3. Clean up existing opportunities with these names to avoid duplicates
opp_names = [
    'Office Design Project - Gemini',
    'Software License Renewal - Deco Addict',
    'Q3 Consultation Services'
]
existing_opps = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', 'in', opp_names]]])
if existing_opps:
    models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_opps])
    print(f"Cleaned up {len(existing_opps)} existing opportunities")

# 4. Create Orphaned Opportunities
# Opp 1: Gemini (In Name)
models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
    'name': 'Office Design Project - Gemini',
    'type': 'opportunity',
    'partner_id': False, # ORPHANED
    'stage_id': stage_id,
    'expected_revenue': 12000,
}])
print("Created 'Office Design Project - Gemini'")

# Opp 2: Deco Addict (In Name)
models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
    'name': 'Software License Renewal - Deco Addict',
    'type': 'opportunity',
    'partner_id': False, # ORPHANED
    'stage_id': stage_id,
    'expected_revenue': 5000,
}])
print("Created 'Software License Renewal - Deco Addict'")

# Opp 3: Azure Interior (In Note only)
azure_opp_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
    'name': 'Q3 Consultation Services',
    'type': 'opportunity',
    'partner_id': False, # ORPHANED
    'stage_id': stage_id,
    'expected_revenue': 8500,
}])
print("Created 'Q3 Consultation Services'")

# Add Note to Azure Opp
models.execute_kw(db, uid, password, 'mail.message', 'create', [{
    'model': 'crm.lead',
    'res_id': azure_opp_id,
    'body': '<p>Note from Sales Director: The client for this project is <b>Azure Interior</b>. Please update the record.</p>',
    'message_type': 'comment',
    'subtype_id': 2, # Note
}])
print("Added note to 'Q3 Consultation Services'")

PYEOF

# Ensure Firefox is running and at pipeline
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="