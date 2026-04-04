#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: update_opportunity_details ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Create the tag "Enterprise" and the opportunity with known initial values
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
uid = common.authenticate(db, user, passwd, {})
if not uid:
    print("ERROR: Authentication failed", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

# 1. Create or find the tag "Enterprise"
tag_ids = models.execute_kw(db, uid, passwd, 'crm.tag', 'search',
    [[['name', '=', 'Enterprise']]])
if not tag_ids:
    tag_id = models.execute_kw(db, uid, passwd, 'crm.tag', 'create',
        [{'name': 'Enterprise', 'color': 3}])
    print(f"Created tag 'Enterprise' with ID: {tag_id}")
else:
    tag_id = tag_ids[0]
    print(f"Tag 'Enterprise' already exists with ID: {tag_id}")

# 2. Find or create a partner "Deco Addict"
partner_ids = models.execute_kw(db, uid, passwd, 'res.partner', 'search',
    [[['name', '=', 'Deco Addict']]])
if not partner_ids:
    partner_id = models.execute_kw(db, uid, passwd, 'res.partner', 'create',
        [{'name': 'Deco Addict', 'is_company': True, 'email': 'info@decoaddict.com',
          'phone': '+1 555-0142', 'city': 'San Francisco', 'country_id': 233}])
    print(f"Created partner 'Deco Addict' with ID: {partner_id}")
else:
    partner_id = partner_ids[0]
    print(f"Partner 'Deco Addict' already exists with ID: {partner_id}")

# 3. Get the first pipeline stage (e.g., "New")
stages = models.execute_kw(db, uid, passwd, 'crm.stage', 'search_read',
    [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence asc', 'limit': 1})
stage_id = stages[0]['id'] if stages else False

# 4. Create or reset the opportunity with known initial values
lead_name = "Office Furniture - Deco Addict"
lead_ids = models.execute_kw(db, uid, passwd, 'crm.lead', 'search',
    [[['name', '=', lead_name]]])

initial_values = {
    'name': lead_name,
    'partner_id': partner_id,
    'type': 'opportunity',
    'expected_revenue': 25000.0,
    'probability': 20.0,
    'priority': '0',
    'tag_ids': [(5, 0, 0)],  # Clear all tags
    'stage_id': stage_id,
    'user_id': uid,
}

if lead_ids:
    models.execute_kw(db, uid, passwd, 'crm.lead', 'write',
        [lead_ids, initial_values])
    lead_id = lead_ids[0]
    print(f"Reset existing opportunity ID: {lead_id}")
else:
    lead_id = models.execute_kw(db, uid, passwd, 'crm.lead', 'create',
        [initial_values])
    print(f"Created new opportunity ID: {lead_id}")

# 5. Disable automated probability so manual edits stick
try:
    models.execute_kw(db, uid, passwd, 'crm.lead', 'write',
        [[lead_id], {'automated_probability': 20.0, 'probability': 20.0}])
except Exception:
    pass

# Save lead_id for verification
with open('/tmp/task_lead_id.txt', 'w') as f:
    f.write(str(lead_id))

print(f"Setup complete. Lead ID: {lead_id}")
PYEOF

# Get the lead ID
LEAD_ID=$(cat /tmp/task_lead_id.txt)
echo "Opportunity ID: $LEAD_ID"

# Ensure Firefox is running and logged in
ensure_firefox_running
sleep 3

# Navigate to the opportunity form view
echo "Navigating to opportunity form..."
# Using action=209 (CRM Pipeline) with specific ID opens the form view
navigate_to_url "${ODOO_URL}/web#id=${LEAD_ID}&model=crm.lead&view_type=form&cids=1&menu_id=139"
sleep 6

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="