#!/bin/bash
echo "=== Setting up supplier_nonconformance_response task ==="

source /workspace/scripts/task_utils.sh

# Step 1: CLEAN — remove stale artifacts from prior runs
rm -f /tmp/supplier_nonconformance_response_result.json
rm -f /tmp/supplier_nonconformance_response_gt.json

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_quality'
user = 'admin'
pwd = 'admin'

# Connect with retries (Lesson 160)
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

def sr(model, domain, fields, limit=100):
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

# CLEAN: Remove target team if it exists from prior run
team_ids = s('quality.alert.team', [['name', '=', 'Supplier Nonconformance Review Board']])
if team_ids:
    d('quality.alert.team', team_ids)
    print(f"Removed stale team (ids={team_ids})")

# CLEAN: Remove target alert if it exists from prior run
alert_ids = s('quality.alert', [['name', 'ilike', 'Systematic Dimensional Variance']])
if alert_ids:
    d('quality.alert', alert_ids)
    print(f"Removed stale target alert (ids={alert_ids})")

# Reset "Material Hardness Below Specification" to New stage
stages = sr('quality.alert.stage', [], ['id', 'name'])
new_stage_id = None
in_progress_stage_id = None
for st in stages:
    nm = st['name'].lower()
    if 'new' in nm or 'open' in nm:
        new_stage_id = st['id']
    if 'progress' in nm:
        in_progress_stage_id = st['id']
if not new_stage_id and stages:
    new_stage_id = stages[0]['id']
if not in_progress_stage_id and len(stages) >= 2:
    in_progress_stage_id = stages[1]['id']

mh_ids = s('quality.alert', [['name', '=', 'Material Hardness Below Specification']])
if mh_ids:
    w('quality.alert', mh_ids, {'stage_id': new_stage_id})
    print(f"Reset 'Material Hardness Below Specification' to New stage")
else:
    # Recreate if missing
    prod_ids = s('product.product', [['name', 'ilike', 'Acoustic Bloc Screens']])
    product_id = prod_ids[0] if prod_ids else None
    data = {
        'name': 'Material Hardness Below Specification',
        'description': 'Material hardness testing shows values 12% below minimum specification threshold. Supplier batch affected: Lot A-2024-112.',
        'priority': '1',
        'stage_id': new_stage_id,
        'corrective_action': 'Affected batch quarantined and supplier notified.',
        'preventive_action': '',
    }
    if product_id:
        data['product_id'] = product_id
    aid = models.execute_kw(db, uid, pwd, 'quality.alert', 'create', [data])
    mh_ids = [aid]
    print(f"Recreated 'Material Hardness Below Specification' id={aid}")

# Reset "Screen Frame Scratch on Delivery" to Normal priority
sf_ids = s('quality.alert', [['name', '=', 'Screen Frame Scratch on Delivery']])
if sf_ids:
    w('quality.alert', sf_ids, {'priority': '0'})
    print(f"Reset 'Screen Frame Scratch on Delivery' to Normal priority")
else:
    prod_ids = s('product.product', [['name', 'ilike', 'Acoustic Bloc Screens']])
    product_id = prod_ids[0] if prod_ids else None
    data = {
        'name': 'Screen Frame Scratch on Delivery',
        'description': '12 of 80 screens from delivery DL-2024-441 show scratches on aluminium frame.',
        'priority': '0',
        'stage_id': new_stage_id,
    }
    if product_id:
        data['product_id'] = product_id
    aid = models.execute_kw(db, uid, pwd, 'quality.alert', 'create', [data])
    sf_ids = [aid]
    print(f"Recreated 'Screen Frame Scratch on Delivery' id={aid}")

# Save ground truth for verifier
gt = {
    'material_hardness_alert_id': mh_ids[0] if mh_ids else None,
    'screen_scratch_alert_id': sf_ids[0] if sf_ids else None,
    'new_stage_id': new_stage_id,
    'in_progress_stage_id': in_progress_stage_id,
}
with open('/tmp/supplier_nonconformance_response_gt.json', 'w') as f:
    json.dump(gt, f)
print(f"Ground truth saved: {gt}")
PYTHON_EOF

# Step 2: RECORD timestamp
date +%s > /tmp/supplier_nonconformance_response_start_ts

# Step 3: Record baseline
record_task_baseline "supplier_nonconformance_response"

# Step 4: Navigate to Odoo home (not quality module — very_hard difficulty)
ensure_firefox "http://localhost:8069/web#action=menu"
sleep 3

take_screenshot /tmp/supplier_nonconformance_response_start.png

echo "=== supplier_nonconformance_response setup complete ==="
