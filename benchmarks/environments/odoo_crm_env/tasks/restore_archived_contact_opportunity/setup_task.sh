#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up: restore_archived_contact_opportunity ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed the contact and then archive it via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
pwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, user, pwd, {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)

    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Check if contact already exists (active or inactive)
    # context={'active_test': False} allows searching for archived records
    existing = models.execute_kw(db, uid, pwd, 'res.partner', 'search',
        [[['name', '=', 'Meridian Technologies']]], {'context': {'active_test': False}})

    # Get state ID for Texas (initial state)
    state_ids = models.execute_kw(db, uid, pwd, 'res.country.state', 'search',
        [[['name', '=', 'Texas'], ['country_id.code', '=', 'US']]])
    texas_id = state_ids[0] if state_ids else False

    # Get US country ID
    us_ids = models.execute_kw(db, uid, pwd, 'res.country', 'search',
        [[['code', '=', 'US']]])
    us_id = us_ids[0] if us_ids else False

    contact_data = {
        'name': 'Meridian Technologies',
        'is_company': True,
        'company_type': 'company',
        'phone': '+1-512-555-0100',
        'email': 'info@meridiantech.example.com',
        'street': '500 Innovation Drive',
        'city': 'Austin',
        'state_id': texas_id,
        'country_id': us_id,
        'zip': '78701',
        'website': 'https://www.meridiantech.example.com',
        'active': True,  # Create as active first
    }

    if existing:
        partner_id = existing[0]
        models.execute_kw(db, uid, pwd, 'res.partner', 'write',
            [[partner_id], contact_data])
        print(f"Updated existing contact ID: {partner_id}")
    else:
        partner_id = models.execute_kw(db, uid, pwd, 'res.partner', 'create', [contact_data])
        print(f"Created contact ID: {partner_id}")

    # Now archive the contact
    models.execute_kw(db, uid, pwd, 'res.partner', 'write',
        [[partner_id], {'active': False}])
    print(f"Archived contact ID: {partner_id}")

    # Remove any existing opportunity with the target name (clean slate)
    existing_opps = models.execute_kw(db, uid, pwd, 'crm.lead', 'search',
        [[['name', '=', 'Meridian Technologies - Enterprise Software Renewal']]])
    if existing_opps:
        models.execute_kw(db, uid, pwd, 'crm.lead', 'unlink', [existing_opps])
        print(f"Removed {len(existing_opps)} pre-existing opportunity/opportunities")

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "Contact seeded and archived."

# Ensure Firefox is running and logged in
# Start at the CRM pipeline (standard view)
ensure_odoo_logged_in "${CRM_PIPELINE_URL}"
sleep 3

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="