#!/bin/bash
set -e
echo "=== Setting up create_hot_lead_server_action task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo
wait_for_odoo

# Prepare Data: Clean existing actions and reset opportunity
python3 - <<'PYEOF'
import xmlrpc.client
import sys

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # 1. CLEANUP: Delete any existing Server Actions named "Mark as Hot Lead"
    action_ids = models.execute_kw('odoodb', uid, 'admin', 'ir.actions.server', 'search',
        [[['name', '=', 'Mark as Hot Lead']]])
    if action_ids:
        models.execute_kw('odoodb', uid, 'admin', 'ir.actions.server', 'unlink', [action_ids])
        print(f"Removed {len(action_ids)} existing server actions.")

    # 2. SETUP: Create/Reset the target Opportunity
    opp_name = "Solar Panel Upgrade - Smith Residence"
    existing_opps = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'search',
        [[['name', '=', opp_name]]])
    
    opp_data = {
        'name': opp_name,
        'type': 'opportunity',
        'priority': '0',       # Low
        'probability': 10.0,   # Low probability
        'expected_revenue': 25000,
        'partner_name': 'Smith Residence',
        'active': True
    }

    if existing_opps:
        models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'write', [existing_opps, opp_data])
        print(f"Reset opportunity '{opp_name}' (ID: {existing_opps[0]})")
    else:
        new_id = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'create', [opp_data])
        print(f"Created opportunity '{opp_name}' (ID: {new_id})")

    # 3. ENSURE DEV MODE IS OFF (Agent must enable it)
    # Note: We can't easily force the UI state of dev mode via RPC, but we start fresh.
    # The default session created by `ensure_odoo_logged_in` does not have ?debug=1

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is open and logged in (Standard mode, not debug)
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="