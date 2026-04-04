#!/bin/bash
set -e
echo "=== Setting up task: consolidate_crm_tags@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Create tags and leads via Python/XML-RPC
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
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

def get_or_create_tag(name, color):
    ids = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', name]]])
    if ids:
        return ids[0]
    return models.execute_kw(db, uid, password, 'crm.tag', 'create', [{'name': name, 'color': color}])

def create_lead(name, partner, revenue, tag_ids):
    # Check if exists and clean it up to ensure fresh state
    ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', name]]])
    if ids:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [ids])
        print(f"Cleaned up existing lead: {name}")
    
    # Create new
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': name,
        'partner_name': partner,
        'expected_revenue': revenue,
        'type': 'opportunity',
        'tag_ids': [[6, 0, tag_ids]]
    }])
    print(f"Created lead: {name}")

# 1. Create Tags
# Standard tag
tag_urgent_id = get_or_create_tag('Urgent', 2) # Gold/Orange
# Bad tags
tag_bad_urgent_id = get_or_create_tag('urgent', 1) # Red
tag_bad_asap_id = get_or_create_tag('ASAP', 4) # Blue

print(f"Tag IDs: Urgent={tag_urgent_id}, urgent={tag_bad_urgent_id}, ASAP={tag_bad_asap_id}")

# 2. Create Opportunities with bad tags
# "Emergency Generators - Apex Corp" -> "urgent"
create_lead('Emergency Generators - Apex Corp', 'Apex Corp', 15000, [tag_bad_urgent_id])

# "Rush Order - Beta Industries" -> "ASAP"
create_lead('Rush Order - Beta Industries', 'Beta Industries', 8500, [tag_bad_asap_id])

# "Expedited Shipping - Gamma Inc" -> "urgent" AND "ASAP"
create_lead('Expedited Shipping - Gamma Inc', 'Gamma Inc', 12000, [tag_bad_urgent_id, tag_bad_asap_id])

# 3. Create a control opportunity (already correct)
create_lead('Control Deal - Delta Co', 'Delta Co', 5000, [tag_urgent_id])

PYEOF

# Ensure Firefox is running and logged in to the pipeline
ensure_odoo_logged_in "${CRM_PIPELINE_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="