#!/bin/bash
set -e
echo "=== Setting up task: consolidate_duplicate_customers@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is ready
wait_for_odoo

# Seed Data via Python
echo "Seeding scenario data..."
python3 - <<PYEOF
import xmlrpc.client
import sys
import time

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Data constants
    MASTER_NAME = "Hyperion Systems Inc."
    DUPE_NAME = "Hyperion Systems"
    EMAIL = "support@hyperion-sys.example.com"
    
    # 1. Clean up existing data to ensure fresh state
    # Find existing partners with these names
    existing_partners = models.execute_kw(db, uid, password, 'res.partner', 'search', 
        [[['name', 'in', [MASTER_NAME, DUPE_NAME]]]])
    
    if existing_partners:
        # Check if linked to leads, remove those leads first to avoid constraints (though unlikely in std Odoo)
        existing_leads = models.execute_kw(db, uid, password, 'crm.lead', 'search',
            [[['partner_id', 'in', existing_partners]]])
        if existing_leads:
             models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_leads])
        
        # Unlink partners
        models.execute_kw(db, uid, password, 'res.partner', 'unlink', [existing_partners])
        print(f"Cleaned up {len(existing_partners)} existing partners")

    # 2. Create Master Partner (Address, No Email)
    master_data = {
        'name': MASTER_NAME,
        'street': '4500 Solar Way',
        'city': 'Phoenix',
        'state_id': 10,  # Arbitrary ID, usually exists in demo data
        'zip': '85001',
        'phone': '(555) 999-0000',
        'email': False,  # Explicitly empty
        'is_company': True,
        'company_type': 'company'
    }
    master_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [master_data])
    print(f"Created Master '{MASTER_NAME}' (ID: {master_id})")

    # 3. Create Duplicate Partner (Email, No Address)
    dupe_data = {
        'name': DUPE_NAME,
        'email': EMAIL,
        'is_company': True,
        'company_type': 'company'
    }
    dupe_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [dupe_data])
    print(f"Created Duplicate '{DUPE_NAME}' (ID: {dupe_id})")

    # 4. Create Opportunities
    # Opp 1: Correctly linked to Master
    opp1 = {
        'name': 'Solar Panel Array - Commercial',
        'partner_id': master_id,
        'expected_revenue': 120000,
        'type': 'opportunity',
        'stage_id': 1
    }
    # Opp 2: Incorrectly linked to Dupe
    opp2 = {
        'name': 'Battery Backup System',
        'partner_id': dupe_id,
        'expected_revenue': 45000,
        'type': 'opportunity',
        'stage_id': 2
    }
    # Opp 3: Incorrectly linked to Dupe
    opp3 = {
        'name': 'Inverter Upgrade',
        'partner_id': dupe_id,
        'expected_revenue': 15000,
        'type': 'opportunity',
        'stage_id': 1
    }

    for opp in [opp1, opp2, opp3]:
        models.execute_kw(db, uid, password, 'crm.lead', 'create', [opp])

    print("Data seeding complete.")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# Ensure Firefox is running and navigate to Contacts (common starting point for cleanup)
# Action 154 is typically Contacts/Partners
ensure_odoo_logged_in "${ODOO_URL}/web#action=154&model=res.partner&view_type=kanban"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="