#!/bin/bash
echo "=== Setting up cross_functional_quality_response task ==="

source /workspace/scripts/task_utils.sh

# Step 1: CLEAN
rm -f /tmp/cross_functional_quality_response_result.json
rm -f /tmp/cross_functional_quality_response_gt.json

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

def sr(model, domain, fields, limit=100):
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

# Get stage IDs
stages = sr('quality.alert.stage', [], ['id', 'name'])
new_id = None
in_progress_id = None
for st in stages:
    nm = st['name'].lower()
    if 'new' in nm or 'open' in nm:
        new_id = st['id']
    if 'progress' in nm:
        in_progress_id = st['id']
if not new_id and stages:
    new_id = stages[0]['id']
if not in_progress_id and len(stages) >= 2:
    in_progress_id = stages[1]['id']

# CLEAN: Remove target alert from prior runs
ids = s('quality.alert', [['name', 'ilike', 'Field Failure']])
if ids:
    d('quality.alert', ids)
    print("Removed stale 'Field Failure' alert")

# CLEAN: Remove target QCP from prior runs
ids = s('quality.point', [['name', 'ilike', 'Bracket Integrity']])
if ids:
    d('quality.point', ids)
    print("Removed stale 'Bracket Integrity' QCP")

# CLEAN: Remove target quality check from prior runs
ids = s('quality.check', [['name', 'ilike', 'Bracket UT Inspection']])
if ids:
    d('quality.check', ids)
    print("Removed stale 'Bracket UT Inspection' check")

# Reset "Screen Frame Scratch on Delivery" to New stage
sf_ids = s('quality.alert', [['name', '=', 'Screen Frame Scratch on Delivery']])
if sf_ids:
    w('quality.alert', sf_ids, {'stage_id': new_id, 'priority': '0'})
    print("Reset 'Screen Frame Scratch on Delivery' to New stage")
else:
    prod_ids = s('product.product', [['name', 'ilike', 'Acoustic Bloc Screens']])
    product_id = prod_ids[0] if prod_ids else None
    data = {
        'name': 'Screen Frame Scratch on Delivery',
        'description': '12 of 80 screens from delivery DL-2024-441 show scratches on aluminium frame.',
        'priority': '0',
        'stage_id': new_id,
    }
    if product_id:
        data['product_id'] = product_id
    aid = models.execute_kw(db, uid, pwd, 'quality.alert', 'create', [data])
    sf_ids = [aid]
    print(f"Recreated 'Screen Frame Scratch on Delivery' id={aid}")

# Reset "Screen Colour Uniformity Audit" to 'none' state
cu_ids = s('quality.check', [['name', '=', 'Screen Colour Uniformity Audit']])
if cu_ids:
    w('quality.check', cu_ids, {'quality_state': 'none'})
    print("Reset 'Screen Colour Uniformity Audit' to To Do state")
else:
    prod_ids = s('product.product', [['name', 'ilike', 'Acoustic Bloc Screens']])
    product_id = prod_ids[0] if prod_ids else None
    data = {'name': 'Screen Colour Uniformity Audit', 'quality_state': 'none'}
    if product_id:
        data['product_id'] = product_id
    cid = models.execute_kw(db, uid, pwd, 'quality.check', 'create', [data])
    print(f"Recreated 'Screen Colour Uniformity Audit' id={cid}")

# Save ground truth
gt = {
    'new_stage_id': new_id,
    'in_progress_stage_id': in_progress_id,
    'screen_scratch_alert_id': sf_ids[0] if sf_ids else None,
}
with open('/tmp/cross_functional_quality_response_gt.json', 'w') as f:
    json.dump(gt, f)
print(f"Ground truth: {gt}")
PYTHON_EOF

# Step 2: RECORD timestamp
date +%s > /tmp/cross_functional_quality_response_start_ts

# Step 3: Record baseline
record_task_baseline "cross_functional_quality_response"

# Step 4: Navigate to Odoo home
ensure_firefox "http://localhost:8069/web#action=menu"
sleep 3

take_screenshot /tmp/cross_functional_quality_response_start.png

echo "=== cross_functional_quality_response setup complete ==="
