#!/bin/bash
echo "=== Setting up incoming_inspection_protocol task ==="

source /workspace/scripts/task_utils.sh

# Step 1: CLEAN
rm -f /tmp/incoming_inspection_protocol_result.json

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

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

# CLEAN: Remove target QCPs from prior runs
for qcp_name in [
    'Structural Integrity Verification - Cabinet',
    'Acoustic Attenuation Test - Screens',
    'Ergonomic Compliance Check - Chair',
]:
    ids = s('quality.point', [['name', '=', qcp_name]])
    if ids:
        d('quality.point', ids)
        print(f"Removed stale QCP '{qcp_name}'")

# Reset quality checks to 'none' state
for check_name in [
    'Visual Inspection - Cabinet Finish',
    'Dimension Verification - Screen Width',
]:
    ids = s('quality.check', [['name', '=', check_name]])
    if ids:
        w('quality.check', ids, {'quality_state': 'none'})
        print(f"Reset check '{check_name}' to 'none'")
    else:
        # Recreate if missing
        prod_name = 'Cabinet with Doors' if 'Cabinet' in check_name else 'Acoustic Bloc Screens'
        prod_ids = s('product.product', [['name', 'ilike', prod_name]])
        product_id = prod_ids[0] if prod_ids else None
        data = {'name': check_name, 'quality_state': 'none'}
        if product_id:
            data['product_id'] = product_id
        cid = models.execute_kw(db, uid, pwd, 'quality.check', 'create', [data])
        print(f"Recreated check '{check_name}' id={cid}")

print("Setup cleanup complete")
PYTHON_EOF

# Step 2: RECORD timestamp
date +%s > /tmp/incoming_inspection_protocol_start_ts

# Step 3: Record baseline
record_task_baseline "incoming_inspection_protocol"

# Step 4: Navigate to Odoo home (very_hard — agent discovers navigation)
ensure_firefox "http://localhost:8069/web#action=menu"
sleep 3

take_screenshot /tmp/incoming_inspection_protocol_start.png

echo "=== incoming_inspection_protocol setup complete ==="
