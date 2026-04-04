#!/bin/bash
set -e
echo "=== Setting up task: highlight_key_account_opportunities@1 ==="

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Source utils
source /workspace/scripts/task_utils.sh

# 3. Ensure Odoo is running
wait_for_odoo

# 4. Seed Data: Create opportunities via Python XML-RPC
# We use a python script to ensure complex logic (finding partners, creating records) is handled reliably
python3 - <<PYEOF
import xmlrpc.client
import sys
import time

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # Helper to find or create partner
    def get_partner_id(name):
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        if ids:
            return ids[0]
        return models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': name}])

    azure_id = get_partner_id("Azure Interior")
    ready_id = get_partner_id("Ready Mat")
    deco_id = get_partner_id("Deco Addict")
    gemini_id = get_partner_id("Gemini Furniture")

    # Get pipeline stages
    stages = models.execute_kw(db, uid, password, 'crm.stage', 'search', [[]])
    if not stages:
        # Should not happen with demo data, but fallback
        new_stage = models.execute_kw(db, uid, password, 'crm.stage', 'create', [{'name': 'New', 'sequence': 1}])
        qual_stage = models.execute_kw(db, uid, password, 'crm.stage', 'create', [{'name': 'Qualified', 'sequence': 2}])
    else:
        new_stage = stages[0]
        qual_stage = stages[1] if len(stages) > 1 else stages[0]

    # Clean up existing opportunities for these partners to ensure a known state
    # (We delete them to avoid confusion with existing demo data)
    partners_to_clean = [azure_id, ready_id, deco_id, gemini_id]
    existing_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['partner_id', 'in', partners_to_clean]]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_ids])
        print(f"Cleaned {len(existing_ids)} existing opportunities")

    # Data to seed
    # List of (Name, PartnerID, ExpectedRevenue, StageID, Priority)
    opportunities = [
        ("Office Expansion Project", azure_id, 25000, new_stage),
        ("Employee Chair Upgrade", ready_id, 4500, new_stage),
        ("Conference Room Redesign", azure_id, 12000, qual_stage),
        ("Lobby Furniture", deco_id, 8000, qual_stage),
        ("Executive Suite Update", azure_id, 35000, new_stage),
        ("Warehouse Shelving", ready_id, 15000, qual_stage),
        ("Reception Desk Renewal", gemini_id, 2200, new_stage),
        ("Break Room Outfitting", azure_id, 6000, qual_stage)
    ]

    created_ids = []
    for name, pid, rev, stage in opportunities:
        new_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
            'name': name,
            'partner_id': pid,
            'expected_revenue': rev,
            'stage_id': stage,
            'color': 0, # Ensure start color is 0 (no color)
            'type': 'opportunity'
        }])
        created_ids.append(new_id)

    print(f"Seeded {len(created_ids)} opportunities successfully.")

    # Save target partner ID for export script
    with open('/tmp/target_partner_id.txt', 'w') as f:
        f.write(str(azure_id))

except Exception as e:
    print(f"Error seeding data: {e}")
    sys.exit(1)
PYEOF

# 5. Open Firefox and navigate to Pipeline
ensure_odoo_logged_in "${CRM_PIPELINE_URL}"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="