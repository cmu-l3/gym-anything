#!/bin/bash
echo "=== Setting up vendor_dispute_documentation task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/vendor_dispute_documentation_result.json
rm -f /tmp/vendor_dispute_documentation_gt.json

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_quality'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(20):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(5)

if not uid:
    print("ERROR: Could not authenticate to Odoo", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def s(model, domain):
    return models.execute_kw(db, uid, pwd, model, 'search', [domain])

def sr(model, domain, fields, limit=200):
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

def c(model, vals):
    return models.execute_kw(db, uid, pwd, model, 'create', [vals])

# Get New stage ID
stages = sr('quality.alert.stage', [], ['id', 'name'])
new_stage_id = None
for st in stages:
    nm = st['name'].lower()
    if 'new' in nm:
        new_stage_id = st['id']
        break
if not new_stage_id and stages:
    new_stage_id = stages[0]['id']

# Delete any existing target alert from prior runs (idempotent reset)
target_name = 'Surface Coating Defect on Cabinet Batch 2025-Q1'
stale = s('quality.alert', [['name', '=', target_name]])
if stale:
    d('quality.alert', stale)
    print(f"Removed stale '{target_name}' alert (ids={stale})")

# Get Cabinet with Doors product
cabinet_ids = s('product.product', [['name', 'ilike', 'Cabinet with Doors']])
cabinet_id = cabinet_ids[0] if cabinet_ids else None

# Create the target alert in New stage, Normal priority, no corrective/preventive, no partner
alert_data = {
    'name': target_name,
    'description': 'Surface coating on Cabinet Batch 2025-Q1 shows uneven coverage and pinholes across 23 of 60 units inspected. Supplier batch reference: SC-2025-B01. DFT readings range 12-55 µm against 35±5 µm specification. Batch quarantined pending regulatory review.',
    'priority': '0',
    'corrective_action': '',
    'preventive_action': '',
}
if cabinet_id:
    alert_data['product_id'] = cabinet_id
if new_stage_id:
    alert_data['stage_id'] = new_stage_id

alert_id = c('quality.alert', alert_data)
print(f"Created '{target_name}' alert (id={alert_id})")

# Remove any stale passfail QCP for Acoustic Bloc Screens from prior runs
screen_ids = s('product.product', [['name', 'ilike', 'Acoustic Bloc Screens']])
screen_id = screen_ids[0] if screen_ids else None

# Look for passfail QCPs associated with Acoustic Bloc Screens that don't exist initially
# Remove any "Coating Inspection" or "Surface Coating" or "Acoustic.*Pass" QCPs
stale_qcps = s('quality.point', [['name', 'ilike', 'Coating'], ['name', 'ilike', 'Acoustic']])
if stale_qcps:
    d('quality.point', stale_qcps)
    print(f"Removed stale coating QCPs for Acoustic Screens (ids={stale_qcps})")
stale_qcps2 = s('quality.point', [['name', 'ilike', 'Surface Coating']])
if stale_qcps2:
    d('quality.point', stale_qcps2)
    print(f"Removed stale Surface Coating QCPs (ids={stale_qcps2})")

# Get any partner that exists in the system for reference
partners = sr('res.partner', [['active', '=', True], ['is_company', '=', True]], ['id', 'name'], limit=5)
partner_ids = [p['id'] for p in partners]
partner_names = [p['name'] for p in partners]

gt = {
    'target_alert_id': alert_id,
    'target_alert_name': target_name,
    'new_stage_id': new_stage_id,
    'screen_product_id': screen_id,
    'available_partner_ids': partner_ids,
    'available_partner_names': partner_names,
}
with open('/tmp/vendor_dispute_documentation_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"Ground truth saved: alert_id={alert_id}, screen_id={screen_id}, partners={partner_names[:3]}")
PYTHON_EOF

date +%s > /tmp/vendor_dispute_documentation_start_ts

record_task_baseline "vendor_dispute_documentation"

ensure_firefox "http://localhost:8069/web#action=quality.action_quality_alert"
sleep 3

take_screenshot /tmp/vendor_dispute_documentation_start.png

echo "=== vendor_dispute_documentation setup complete ==="
