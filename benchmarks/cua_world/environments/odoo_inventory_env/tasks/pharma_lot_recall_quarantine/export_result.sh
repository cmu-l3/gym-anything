#!/bin/bash
# Export script for pharma_lot_recall_quarantine task
# Queries Odoo database for: quarantine location, lot locations/quantities,
# purchase orders to SafePharm, and control product state.

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/pharma_recall_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")
RESULT_FILE="/tmp/pharma_recall_result.json"

take_screenshot "/tmp/pharma_recall_final.png" ga || true

python3 << PYEOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
username = 'admin'
password = 'admin'
task_start = int('$TASK_START')

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url), allow_none=True)
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url), allow_none=True)
except Exception as e:
    with open('$RESULT_FILE', 'w') as f:
        json.dump({'error': str(e)}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs or {})


# ============================================================
# 1. Get WH/Stock location
# ============================================================
wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
wh_stock_id = wh[0]['lot_stock_id'][0] if wh else None

# ============================================================
# 2. Find quarantine location
# ============================================================
quarantine_locs = execute('stock.location', 'search_read',
    [[['name', 'ilike', 'Quarantine'], ['usage', '=', 'internal']]],
    {'fields': ['id', 'name', 'location_id', 'complete_name']})

quarantine_id = None
quarantine_is_child_of_wh_stock = False

# Prefer a quarantine location that is a child of WH/Stock
# First pass: look for exact child of WH/Stock
for qloc in quarantine_locs:
    if qloc['location_id'] and qloc['location_id'][0] == wh_stock_id:
        quarantine_id = qloc['id']
        quarantine_is_child_of_wh_stock = True
        break
# Fallback: take any quarantine location
if quarantine_id is None and quarantine_locs:
    quarantine_id = quarantine_locs[0]['id']

# ============================================================
# 3. Check each lot's current location and quantity
# ============================================================
lot_names = [
    'AMX-2024-041', 'AMX-2024-067', 'AMX-2024-089',
    'IBU-2024-033', 'IBU-2024-112',
    'CET-2024-015', 'CET-2024-071',
    'MET-2024-022', 'MET-2024-045',
    'OMP-2024-019',
]

lots_data = {}
for lot_name in lot_names:
    lot_records = execute('stock.lot', 'search_read',
        [[['name', '=', lot_name]]],
        {'fields': ['id', 'product_id']})

    if not lot_records:
        lots_data[lot_name] = {'found': False}
        continue

    lot_id = lot_records[0]['id']
    product_id = lot_records[0]['product_id'][0]

    # Quantity in WH/Stock
    wh_quants = execute('stock.quant', 'search_read',
        [[['lot_id', '=', lot_id], ['location_id', '=', wh_stock_id]]],
        {'fields': ['quantity']})
    wh_qty = sum(q['quantity'] for q in wh_quants)

    # Quantity in quarantine location (if found)
    q_qty = 0
    if quarantine_id:
        q_quants = execute('stock.quant', 'search_read',
            [[['lot_id', '=', lot_id], ['location_id', '=', quarantine_id]]],
            {'fields': ['quantity']})
        q_qty = sum(q['quantity'] for q in q_quants)

    # Total quantity across ALL internal locations
    all_quants = execute('stock.quant', 'search_read',
        [[['lot_id', '=', lot_id],
          ['location_id.usage', '=', 'internal']]],
        {'fields': ['quantity', 'location_id']})
    total_qty = sum(q['quantity'] for q in all_quants)

    lots_data[lot_name] = {
        'found': True,
        'lot_id': lot_id,
        'product_id': product_id,
        'wh_stock_qty': wh_qty,
        'quarantine_qty': q_qty,
        'total_internal_qty': total_qty,
    }

# ============================================================
# 4. Check Purchase Orders to SafePharm Industries
# ============================================================
safepharm = execute('res.partner', 'search_read',
    [[['name', '=', 'SafePharm Industries']]],
    {'fields': ['id'], 'limit': 1})
safepharm_id = safepharm[0]['id'] if safepharm else None

po_data = {
    'safepharm_found': safepharm_id is not None,
    'purchase_orders': [],
    'po_lines_by_product': {},
}

if safepharm_id:
    # Find all POs to SafePharm in confirmed or done state
    pos = execute('purchase.order', 'search_read',
        [[['partner_id', '=', safepharm_id],
          ['state', 'in', ['purchase', 'done']]]],
        {'fields': ['id', 'name', 'state']})

    for po in pos:
        lines = execute('purchase.order.line', 'search_read',
            [[['order_id', '=', po['id']]]],
            {'fields': ['product_id', 'product_qty']})

        po_entry = {
            'po_id': po['id'],
            'po_name': po['name'],
            'state': po['state'],
            'lines': [],
        }

        for line in lines:
            pid = line['product_id'][0]
            pname = line['product_id'][1]

            # Find product code
            tmpl = execute('product.product', 'read', [[pid]],
                {'fields': ['default_code']})
            prod_code = tmpl[0]['default_code'] if tmpl else 'UNKNOWN'

            po_entry['lines'].append({
                'product_id': pid,
                'product_code': prod_code,
                'product_name': pname,
                'qty': line['product_qty'],
            })

            # Accumulate by product code
            if prod_code not in po_data['po_lines_by_product']:
                po_data['po_lines_by_product'][prod_code] = 0
            po_data['po_lines_by_product'][prod_code] += line['product_qty']

        po_data['purchase_orders'].append(po_entry)

    # Also check for draft POs (not confirmed)
    draft_pos = execute('purchase.order', 'search_read',
        [[['partner_id', '=', safepharm_id],
          ['state', 'in', ['draft', 'sent']]]],
        {'fields': ['id', 'name', 'state']})
    po_data['draft_po_count'] = len(draft_pos)

# ============================================================
# 5. Assemble result
# ============================================================
result = {
    'task_start': task_start,
    'wh_stock_id': wh_stock_id,
    'quarantine': {
        'found': quarantine_id is not None,
        'quarantine_id': quarantine_id,
        'is_child_of_wh_stock': quarantine_is_child_of_wh_stock,
        'details': quarantine_locs,
    },
    'lots': lots_data,
    'purchase_orders': po_data,
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
os.chmod('$RESULT_FILE', 0o666)

print("Export complete. Result saved to $RESULT_FILE")
print(json.dumps(result, indent=2))
PYEOF
