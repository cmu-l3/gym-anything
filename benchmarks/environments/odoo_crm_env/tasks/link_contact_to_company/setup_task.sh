#!/bin/bash
set -e
echo "=== Setting up task: link_contact_to_company@1 ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is ready
wait_for_odoo

# Seed data via Python XML-RPC
# We create a Company and an Independent Contact, plus an Opportunity
python3 - <<PYEOF
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoodb'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # 1. Check/Create Company 'Stratosphere Solutions'
    # Ensure it exists and has no children initially
    company_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', 
        [[['name', '=', 'Stratosphere Solutions'], ['is_company', '=', True]]])
        
    if not company_ids:
        company_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
            'name': 'Stratosphere Solutions',
            'is_company': True,
            'street': '100 Cloud Way',
            'city': 'San Francisco',
            'state_id': 13, # CA (approx ID, fallback safe)
            'zip': '94105',
            'email': 'info@stratosphere.example.com'
        }])
        print(f"Created Company: {company_id}")
    else:
        company_id = company_ids[0]
        # Clean state: remove children to ensure Elena isn't already linked
        # We don't delete children, just unlink them or ensure Elena isn't one of them
        pass

    # 2. Check/Create Individual 'Elena Grigoryeva' (Standalone)
    # First, delete if she exists to ensure clean slate and no duplicates
    existing_elena = models.execute_kw(db, uid, password, 'res.partner', 'search', 
        [[['name', '=', 'Elena Grigoryeva']]])
    if existing_elena:
        models.execute_kw(db, uid, password, 'res.partner', 'unlink', [existing_elena])
        print("Removed existing Elena record")

    elena_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
        'name': 'Elena Grigoryeva',
        'is_company': False,
        'email': 'elena.g@stratosphere.example.com',
        'function': 'Consultant', # Wrong initial job
        'parent_id': False # Explicitly no parent
    }])
    print(f"Created Contact: {elena_id}")

    # 3. Create Opportunity linked to Elena
    # Delete existing opp if any
    existing_opp = models.execute_kw(db, uid, password, 'crm.lead', 'search', 
        [[['name', '=', 'Cloud Migration - Stratosphere']]])
    if existing_opp:
         models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_opp])

    opp_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': 'Cloud Migration - Stratosphere',
        'type': 'opportunity',
        'partner_id': elena_id,
        'expected_revenue': 125000,
        'probability': 20,
        'description': 'Migration of legacy on-prem servers to cloud infrastructure.',
    }])
    print(f"Created Opportunity: {opp_id}")

    # Save IDs for export script to verify exact records
    with open('/tmp/task_ids.txt', 'w') as f:
        f.write(f"COMPANY_ID={company_id}\n")
        f.write(f"CONTACT_ID={elena_id}\n")
        f.write(f"OPP_ID={opp_id}\n")

except Exception as e:
    print(f"RPC Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="