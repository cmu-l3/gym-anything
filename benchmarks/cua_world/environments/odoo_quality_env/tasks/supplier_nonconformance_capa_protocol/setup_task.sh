#!/bin/bash
echo "=== Setting up supplier_nonconformance_capa_protocol task ==="

source /workspace/scripts/task_utils.sh

# Step 1: CLEAN stale outputs
rm -f /tmp/supplier_nonconformance_capa_result.json
rm -f /tmp/supplier_nonconformance_capa_gt.json

# Step 2: Setup data via XML-RPC
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
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain],
                             {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

def c(model, vals):
    return models.execute_kw(db, uid, pwd, model, 'create', [vals])

# --- Ensure vendor "Gemini Furniture" exists ---
partner_ids = s('res.partner', [['name', '=', 'Gemini Furniture']])
if partner_ids:
    gemini_id = partner_ids[0]
    print(f"Found vendor Gemini Furniture (id={gemini_id})")
else:
    gemini_id = c('res.partner', {'name': 'Gemini Furniture', 'company_type': 'company'})
    print(f"Created vendor Gemini Furniture (id={gemini_id})")

# --- Ensure products exist ---
cabinet_ids = s('product.product', [['name', 'ilike', 'Cabinet with Doors']])
if not cabinet_ids:
    tmpl_id = c('product.template', {'name': 'Cabinet with Doors', 'type': 'product'})
    cabinet_ids = s('product.product', [['product_tmpl_id', '=', tmpl_id]])
cabinet_id = cabinet_ids[0]
print(f"Cabinet with Doors id={cabinet_id}")

screens_ids = s('product.product', [['name', 'ilike', 'Acoustic Bloc Screens']])
if not screens_ids:
    tmpl_id = c('product.template', {'name': 'Acoustic Bloc Screens', 'type': 'product'})
    screens_ids = s('product.product', [['product_tmpl_id', '=', tmpl_id]])
screens_id = screens_ids[0]
print(f"Acoustic Bloc Screens id={screens_id}")

# --- Get Receipts picking type ---
picking_ids = s('stock.picking.type', [['code', '=', 'incoming']])
receipts_id = picking_ids[0] if picking_ids else False
print(f"Receipts picking type id={receipts_id}")

# --- Delete stale task artifacts ---
stale = s('quality.alert', [['name', 'ilike', 'Lot NCR-2024-1247']])
if stale:
    d('quality.alert', stale)
    print(f"Removed stale alert(s): {stale}")

for pattern in ['Weld Integrity Verification', 'Surface Finish Gate']:
    stale = s('quality.point', [['name', 'ilike', pattern]])
    if stale:
        d('quality.point', stale)
        print(f"Removed stale QCP(s) matching '{pattern}': {stale}")

stale = s('quality.alert.team', [['name', '=', 'Supplier Incident Response']])
if stale:
    d('quality.alert.team', stale)
    print(f"Removed stale team: {stale}")

# --- Reset quality check to pending state ---
check_ids = s('quality.check', [['name', '=', 'Visual Inspection - Cabinet Finish']])
if check_ids:
    w('quality.check', check_ids, {'quality_state': 'none'})
    check_id = check_ids[0]
    print(f"Reset check 'Visual Inspection - Cabinet Finish' to none (id={check_id})")
else:
    qcp_ids = s('quality.point', [['name', 'ilike', 'Incoming Parts Verification']])
    point_id = qcp_ids[0] if qcp_ids else False
    check_id = c('quality.check', {
        'name': 'Visual Inspection - Cabinet Finish',
        'product_id': cabinet_id,
        'quality_state': 'none',
        'point_id': point_id,
    })
    print(f"Recreated check 'Visual Inspection - Cabinet Finish' (id={check_id})")

# --- Get stage IDs ---
stages = sr('quality.alert.stage', [], ['id', 'name'])
stage_ids = {}
for st in stages:
    nm = st['name'].lower()
    if 'new' in nm or 'open' in nm:
        stage_ids['new'] = st['id']
    elif 'progress' in nm:
        stage_ids['in_progress'] = st['id']
    elif 'done' in nm or 'close' in nm:
        stage_ids['done'] = st['id']
print(f"Stage IDs: {stage_ids}")

# --- Save ground truth ---
gt = {
    'gemini_id': gemini_id,
    'cabinet_id': cabinet_id,
    'screens_id': screens_id,
    'receipts_id': receipts_id,
    'check_id': check_id,
    'stage_ids': stage_ids,
}
with open('/tmp/supplier_nonconformance_capa_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"Ground truth saved: {json.dumps(gt)}")
PYTHON_EOF

# Step 3: Record timestamp AFTER data cleanup
date +%s > /tmp/supplier_nonconformance_capa_start_ts

# Step 4: Record baseline counts
record_task_baseline "supplier_nonconformance_capa"

# Step 5: Navigate Firefox to Odoo home
ensure_firefox "http://localhost:8069/web"
sleep 3

take_screenshot /tmp/supplier_nonconformance_capa_start.png

echo "=== supplier_nonconformance_capa_protocol setup complete ==="
