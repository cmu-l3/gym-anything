#!/bin/bash
echo "=== Setting up schedule_activity task ==="

source /workspace/scripts/task_utils.sh

# Wait for Odoo to be ready
wait_for_odoo

# Ensure the CloudServices Partnership opportunity exists and has no pending activities
python3 - <<'PYEOF'
import xmlrpc.client

common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('odoodb', 'admin', 'admin', {})
models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

opp_name = 'CloudServices Partnership'

# Get Qualified stage
stages = models.execute_kw('odoodb', uid, 'admin', 'crm.stage', 'search_read',
    [[['name', 'ilike', 'Qualified']]], {'fields': ['id', 'name', 'sequence'], 'limit': 1})
stage_id = stages[0]['id'] if stages else None
print(f"Stage: {stages[0]['name'] if stages else 'default'} (ID={stage_id})")

# Find or create the opportunity
existing = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'search',
    [[['name', '=', opp_name]]])

data = {
    'name': opp_name,
    'partner_name': 'Vertex Solutions Corp',
    'type': 'opportunity',
    'expected_revenue': 120000,
    'email_from': 'partnerships@vertex-solutions.com',
    'phone': '+1 (312) 555-0456',
    'description': 'Strategic cloud services partnership opportunity.',
    'probability': 40,
    'active': True,
}
if stage_id:
    data['stage_id'] = stage_id

if existing:
    models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'write', [existing, data])
    opp_id = existing[0]
    print(f"Reset opportunity '{opp_name}' (ID={opp_id})")

    # Remove any existing scheduled activities for this record
    activities = models.execute_kw('odoodb', uid, 'admin', 'mail.activity', 'search',
        [[['res_model', '=', 'crm.lead'], ['res_id', '=', opp_id]]])
    if activities:
        models.execute_kw('odoodb', uid, 'admin', 'mail.activity', 'unlink', [activities])
        print(f"Removed {len(activities)} existing activities")
else:
    opp_id = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'create', [data])
    print(f"Created opportunity '{opp_name}' (ID={opp_id})")

opp = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'read',
    [[opp_id]], {'fields': ['id', 'name', 'type', 'stage_id', 'activity_ids']})[0]
print(f"Opportunity state: {opp}")

with open('/tmp/task_opp_id.txt', 'w') as f:
    f.write(str(opp_id))
PYEOF

OPP_ID=$(cat /tmp/task_opp_id.txt 2>/dev/null || echo "")

# Navigate to CRM and then to specific opportunity
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 3

if [ -n "$OPP_ID" ]; then
    navigate_to_url "http://localhost:8069/web#action=209&id=${OPP_ID}&model=crm.lead&view_type=form&cids=1&menu_id=139"
    sleep 4
fi

# Take screenshot to verify start state
take_screenshot /tmp/schedule_activity_start.png
echo "Start state screenshot saved to /tmp/schedule_activity_start.png"

echo "=== schedule_activity task setup complete ==="
