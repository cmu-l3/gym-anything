#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up add_contact_to_opportunity task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# ===== Database Setup via Python/XMLRPC =====
# This script ensures:
# 1. Company 'Gemini Furniture' exists
# 2. Opportunity 'Office Furniture Bulk Order' exists and is linked to Gemini
# 3. 'Patricia Williams' does NOT exist (clean slate)

python3 << 'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)

    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- 1. Ensure "Gemini Furniture" company contact exists ---
    gemini_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
        [[['name', '=', 'Gemini Furniture'], ['is_company', '=', True]]])

    if gemini_ids:
        gemini_id = gemini_ids[0]
        print(f"Gemini Furniture exists: {gemini_id}")
    else:
        gemini_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
            'name': 'Gemini Furniture',
            'is_company': True,
            'street': '317 Fairchild Dr',
            'city': 'Mountain View',
            'zip': '94043',
            'country_id': 233,  # US
            'phone': '+1 650-555-0100',
            'email': 'info@geminifurniture.example.com',
            'website': 'https://www.geminifurniture.example.com',
        }])
        print(f"Created Gemini Furniture: {gemini_id}")

    # --- 2. Remove any existing "Patricia Williams" to ensure clean state ---
    # Also reset any opportunities linked to her back to Gemini
    patricia_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
        [[['name', '=', 'Patricia Williams']]])
    
    if patricia_ids:
        # Check if linked to any leads/opportunities
        leads_with_patricia = models.execute_kw(db, uid, password, 'crm.lead', 'search',
            [[['partner_id', 'in', patricia_ids]]])
        
        if leads_with_patricia:
            # Revert these leads to the company
            models.execute_kw(db, uid, password, 'crm.lead', 'write',
                [leads_with_patricia, {'partner_id': gemini_id}])
            print(f"Reset {len(leads_with_patricia)} leads back to Gemini Furniture")
            
        # Unlink (delete) the contact
        models.execute_kw(db, uid, password, 'res.partner', 'unlink', [patricia_ids])
        print(f"Removed existing Patricia Williams contact(s)")

    # --- 3. Create or update the "Office Furniture Bulk Order" opportunity ---
    # Get a stage (Qualified or Proposition)
    stages = models.execute_kw(db, uid, password, 'crm.stage', 'search_read',
        [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})
    
    # Try to find 'Qualified' or just pick the 2nd stage
    stage_id = stages[1]['id'] if len(stages) > 1 else stages[0]['id']
    for s in stages:
        if 'Qualified' in s['name']:
            stage_id = s['id']
            break

    opp_name = "Office Furniture Bulk Order"
    existing_opp = models.execute_kw(db, uid, password, 'crm.lead', 'search',
        [[['name', '=', opp_name]]])

    opp_data = {
        'name': opp_name,
        'partner_id': gemini_id, # Must start linked to Company
        'type': 'opportunity',
        'expected_revenue': 45000.0,
        'probability': 40.0,
        'stage_id': stage_id,
        'description': 'Gemini Furniture is looking to order office furniture in bulk.',
        'email_from': 'info@geminifurniture.example.com',
        'phone': '+1 650-555-0100',
    }

    if existing_opp:
        models.execute_kw(db, uid, password, 'crm.lead', 'write',
            [existing_opp, opp_data])
        opp_id = existing_opp[0]
        print(f"Reset opportunity '{opp_name}' (ID: {opp_id})")
    else:
        opp_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [opp_data])
        print(f"Created opportunity '{opp_name}' (ID: {opp_id})")

    # Save IDs to files for verification later (optional, but good for debugging)
    with open('/tmp/task_gemini_id.txt', 'w') as f:
        f.write(str(gemini_id))
    with open('/tmp/task_opp_id.txt', 'w') as f:
        f.write(str(opp_id))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# ===== Browser Setup =====
# Ensure Firefox is running and logged in
ensure_odoo_logged_in "$CRM_PIPELINE_URL"
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus Firefox
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="