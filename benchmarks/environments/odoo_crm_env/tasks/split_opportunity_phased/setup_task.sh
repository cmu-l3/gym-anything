#!/bin/bash
set -e
echo "=== Setting up split_opportunity_phased task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed the specific opportunity for this task
echo "Seeding initial opportunity data..."
python3 - <<PYEOF
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure Partner Exists
    partner_id = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', 'Azure Interior']]])
    if not partner_id:
        partner_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': 'Azure Interior', 'is_company': True}])
        print(f"Created partner: {partner_id}")
    else:
        partner_id = partner_id[0]

    # 2. Cleanup: Remove any existing target records to ensure clean state
    # We remove any potential previous attempts at Phase 1 or Phase 2
    to_remove = models.execute_kw(db, uid, password, 'crm.lead', 'search', 
        [[['name', 'in', ['Azure Interior - Design Phase', 'Azure Interior - Implementation Phase']]]])
    if to_remove:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [to_remove])
        print(f"Cleaned up {len(to_remove)} existing target records")

    # 3. Create/Reset the Seed Opportunity
    # We look for the "Whole Office Design" opp. If it exists, reset it. If not, create it.
    seed_opp_name = 'Azure Interior - Whole Office Design'
    seed_opp_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', seed_opp_name]]])
    
    seed_data = {
        'name': seed_opp_name,
        'partner_id': partner_id,
        'expected_revenue': 120000,
        'type': 'opportunity',
        'probability': 20,
        'stage_id': 1, # New/Qualified usually
        'date_deadline': False # Clear date so agent has to set it
    }

    if seed_opp_ids:
        models.execute_kw(db, uid, password, 'crm.lead', 'write', [seed_opp_ids, seed_data])
        print(f"Reset seed opportunity: {seed_opp_ids[0]}")
        opp_id = seed_opp_ids[0]
    else:
        opp_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [seed_data])
        print(f"Created seed opportunity: {opp_id}")

    # Write ID to file for navigation
    with open('/tmp/target_opp_id.txt', 'w') as f:
        f.write(str(opp_id))

except Exception as e:
    print(f"Error seeding data: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

TARGET_OPP_ID=$(cat /tmp/target_opp_id.txt 2>/dev/null || echo "")

# Launch Firefox and login
# We navigate directly to the specific opportunity form to save the agent search time
# and ensure they start at the right place
TARGET_URL="http://localhost:8069/web#action=209&id=${TARGET_OPP_ID}&model=crm.lead&view_type=form&cids=1&menu_id=139"
ensure_odoo_logged_in "$TARGET_URL"

# Maximize Firefox (ensure_odoo_logged_in starts it, but we enforce maximization here)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="