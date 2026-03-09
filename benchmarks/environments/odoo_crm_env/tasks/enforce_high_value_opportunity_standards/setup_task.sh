#!/bin/bash
set -e
echo "=== Setting up enforce_high_value_opportunity_standards ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed Data using Python/XML-RPC
# We use a python script to ensure precise control over data creation
python3 - <<PYEOF
import xmlrpc.client
import sys

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # 1. Clean up potential previous run data
    target_names = ['Global Logistics Contract', 'New HQ Furniture', 'Server Upgrade', 'Q3 Marketing Campaign']
    existing_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search',
        [[['name', 'in', target_names]]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing records")

    # 2. Ensure "Key Account" tag exists (so agent can select it, or they can re-create it)
    # We create it to avoid ambiguity about tag color/properties, but agent still needs to apply it.
    tag_ids = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', 'Key Account']]])
    if not tag_ids:
        key_account_id = models.execute_kw(db, uid, password, 'crm.tag', 'create', [{'name': 'Key Account', 'color': 4}])
        print(f"Created 'Key Account' tag: {key_account_id}")
    else:
        key_account_id = tag_ids[0]
        print(f"Found 'Key Account' tag: {key_account_id}")

    # 3. Create Opportunities

    # Deal A: $150k, Needs Fix (Low Prio, No Tag)
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': 'Global Logistics Contract',
        'partner_name': 'Gemini Furniture',
        'expected_revenue': 150000,
        'priority': '0', # Normal/Low
        'type': 'opportunity',
        'stage_id': 1 # New
    }])

    # Deal B: $55k, Needs Fix (Low Prio, No Tag)
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': 'New HQ Furniture',
        'partner_name': 'Azure Interior',
        'expected_revenue': 55000,
        'priority': '0', # Normal/Low
        'type': 'opportunity',
        'stage_id': 2 # Qualified
    }])

    # Deal C: $12k, Ignore (Low Prio, No Tag) - Control Case
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': 'Server Upgrade',
        'partner_name': 'Deco Addict',
        'expected_revenue': 12000,
        'priority': '0', # Normal/Low
        'type': 'opportunity',
        'stage_id': 1 # New
    }])

    # Deal D: $75k, Already Compliant (High Prio, Has Tag) - Context/Example
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': 'Q3 Marketing Campaign',
        'partner_name': 'Lumber Inc',
        'expected_revenue': 75000,
        'priority': '1', # High/Starred
        'tag_ids': [(4, key_account_id)],
        'type': 'opportunity',
        'stage_id': 3 # Proposition
    }])

    print("Data seeding complete.")

except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
PYEOF

# Record initial count of "Key Account" tagged items for reference
odoo_db_query "SELECT count(*) FROM crm_tag_rel r JOIN crm_tag t ON r.tag_id = t.id WHERE t.name = 'Key Account'" > /tmp/initial_key_account_count.txt

# Launch Firefox and login
# We navigate to the pipeline view (action=209)
ensure_odoo_logged_in "${CRM_PIPELINE_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="