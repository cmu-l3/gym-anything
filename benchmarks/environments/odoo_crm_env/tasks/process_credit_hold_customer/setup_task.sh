#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Process Customer Credit Hold ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Ensure clean state using Python XML-RPC
# We need to remove the specific tag, lost reason, and reset the opportunity/customer if they exist
python3 << 'PYEOF'
import xmlrpc.client
import ssl

# Odoo Connection details
url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
uid = common.authenticate(db, username, password, {})
models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

# 1. Clean up 'Credit Issues' Lost Reason if exists
reason_ids = models.execute_kw(db, uid, password, 'crm.lost.reason', 'search', [[['name', '=', 'Credit Issues']]])
if reason_ids:
    models.execute_kw(db, uid, password, 'crm.lost.reason', 'unlink', [reason_ids])
    print(f"Removed {len(reason_ids)} existing lost reasons")

# 2. Clean up 'Credit Hold' Tag if exists
tag_ids = models.execute_kw(db, uid, password, 'res.partner.category', 'search', [[['name', '=', 'Credit Hold']]])
if tag_ids:
    # First remove tag from all partners to avoid constraint issues (though unlink handles cascade usually)
    partners_with_tag = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['category_id', 'in', tag_ids]]])
    if partners_with_tag:
        models.execute_kw(db, uid, password, 'res.partner', 'write', [partners_with_tag, {'category_id': [(3, tag_id) for tag_id in tag_ids]}])
    
    models.execute_kw(db, uid, password, 'res.partner.category', 'unlink', [tag_ids])
    print(f"Removed {len(tag_ids)} existing tags")

# 3. Create/Reset Customer 'Gemini Furniture'
partner_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', 'Gemini Furniture']]])
if partner_ids:
    partner_id = partner_ids[0]
    # Clear tags
    models.execute_kw(db, uid, password, 'res.partner', 'write', [[partner_id], {'category_id': [[6, 0, []]]}])
    print(f"Reset existing partner {partner_id}")
else:
    partner_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': 'Gemini Furniture', 'is_company': True}])
    print(f"Created new partner {partner_id}")

# 4. Create/Reset Opportunity 'Gemini - Office Chairs'
lead_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', 'Gemini - Office Chairs']]])
if lead_ids:
    lead_id = lead_ids[0]
    models.execute_kw(db, uid, password, 'crm.lead', 'write', [[lead_id], {
        'active': True,
        'partner_id': partner_id,
        'lost_reason_id': False,
        'probability': 10.0
    }])
    print(f"Reset existing lead {lead_id}")
else:
    lead_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': 'Gemini - Office Chairs',
        'partner_id': partner_id,
        'type': 'opportunity',
        'expected_revenue': 12500.0,
        'probability': 10.0
    }])
    print(f"Created new lead {lead_id}")

PYEOF

# Launch Firefox and log in
ensure_odoo_logged_in "http://localhost:8069/web"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="