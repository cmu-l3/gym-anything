#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/vendor_disruption_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/vendor_disruption_final.png" || true

python3 << PYEOF
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

task_start = int(os.environ.get('TASK_START', '0'))

# Load initial state
try:
    with open('/tmp/vendor_disruption_initial_state.json') as f:
        initial_state = json.load(f)
except Exception:
    initial_state = {}

# Get warehouse
wh = execute('stock.warehouse', 'search_read', [[]], fields=['id', 'lot_stock_id'], limit=1)
wh_id = wh[0]['id']
stock_loc_id = wh[0]['lot_stock_id'][0]

# Get vendor IDs
precision_vendor = execute('res.partner', 'search_read',
                           [[['name', '=', 'Precision Aeroparts Inc.']]],
                           fields=['id'], limit=1)
precision_id = precision_vendor[0]['id'] if precision_vendor else None

skytech_vendor = execute('res.partner', 'search_read',
                         [[['name', '=', 'SkyTech Components Ltd.']]],
                         fields=['id'], limit=1)
skytech_id = skytech_vendor[0]['id'] if skytech_vendor else None

aeroalloy_vendor = execute('res.partner', 'search_read',
                           [[['name', '=', 'AeroAlloy Materials Corp.']]],
                           fields=['id'], limit=1)
aeroalloy_id = aeroalloy_vendor[0]['id'] if aeroalloy_vendor else None

# Backup vendor mapping
backup_vendor_map = {
    'AERO-BRK-001': skytech_id,
    'AERO-HYD-002': skytech_id,
    'AERO-TRB-003': aeroalloy_id,
    'AERO-FAS-004': aeroalloy_id,
}

affected_codes = ['AERO-BRK-001', 'AERO-HYD-002', 'AERO-TRB-003', 'AERO-FAS-004']
unaffected_codes = ['AERO-AVN-005', 'AERO-CMP-006', 'AERO-RVT-007',
                    'AERO-BRG-008', 'AERO-SEL-009', 'AERO-SHM-010']
protected_po_products = ['AERO-CMP-006', 'AERO-SEL-009']
original_quantities = {
    'AERO-BRK-001': 25,
    'AERO-HYD-002': 40,
    'AERO-TRB-003': 15,
    'AERO-FAS-004': 100,
}

result = {
    'task_start': task_start,
    'vendor_ids': {
        'precision': precision_id,
        'skytech': skytech_id,
        'aeroalloy': aeroalloy_id,
    },
    'products': {},
}

all_codes = affected_codes + unaffected_codes

for code in all_codes:
    tmpl = execute('product.template', 'search_read',
                   [[['default_code', '=', code]]],
                   fields=['id', 'name', 'product_variant_ids'], limit=1)
    if not tmpl:
        result['products'][code] = {'found': False}
        continue

    tmpl_id = tmpl[0]['id']
    prod_id = tmpl[0]['product_variant_ids'][0]
    prod_name = tmpl[0]['name']

    # Current stock quantity
    quants = execute('stock.quant', 'search_read',
                     [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]],
                     fields=['quantity'])
    current_qty = sum(q['quantity'] for q in quants)

    # All POs for this product
    po_lines = execute('purchase.order.line', 'search_read',
                       [[['product_id', '=', prod_id]]],
                       fields=['order_id', 'product_qty', 'price_unit'])

    po_details = []
    for line in po_lines:
        po_id = line['order_id'][0]
        po_data = execute('purchase.order', 'read', [[po_id]],
                          fields=['state', 'partner_id', 'name'])[0]
        po_details.append({
            'po_id': po_id,
            'po_name': po_data['name'],
            'state': po_data['state'],
            'partner_id': po_data['partner_id'][0],
            'partner_name': po_data['partner_id'][1],
            'qty': line['product_qty'],
        })

    # Categorize POs
    cancelled_precision_pos = [p for p in po_details
                                if p['partner_id'] == precision_id and p['state'] == 'cancel']
    active_precision_pos = [p for p in po_details
                             if p['partner_id'] == precision_id and p['state'] not in ('cancel',)]
    new_backup_pos = [p for p in po_details
                       if p['partner_id'] != precision_id and p['state'] in ('purchase', 'done')]
    new_backup_draft_pos = [p for p in po_details
                             if p['partner_id'] != precision_id and p['state'] in ('draft', 'sent')]

    # Determine correct backup vendor for this product
    expected_backup_id = backup_vendor_map.get(code)
    has_correct_backup_po = any(
        p['partner_id'] == expected_backup_id and p['state'] in ('purchase', 'done')
        for p in po_details
    ) if expected_backup_id else False
    backup_po_qty = sum(
        p['qty'] for p in po_details
        if p['partner_id'] == expected_backup_id and p['state'] in ('purchase', 'done')
    ) if expected_backup_id else 0

    # Reorder rules
    rules = execute('stock.warehouse.orderpoint', 'search_read',
                    [[['product_id', '=', prod_id], ['active', '=', True]]],
                    fields=['product_min_qty', 'product_max_qty'])
    has_reorder_rule = len(rules) > 0

    # Check if reorder rule's vendor supplier info points to backup vendor
    # We check supplierinfo on the product template for the backup vendor
    reorder_vendor_updated = False
    if expected_backup_id and has_reorder_rule:
        supplier_infos = execute('product.supplierinfo', 'search_read',
                                  [[['product_tmpl_id', '=', tmpl_id]]],
                                  fields=['partner_id', 'sequence'])
        # Check if backup vendor is listed and has lower or equal sequence than disrupted vendor
        backup_info = [s for s in supplier_infos if s['partner_id'][0] == expected_backup_id]
        precision_info = [s for s in supplier_infos if s['partner_id'][0] == precision_id]
        if backup_info:
            if not precision_info:
                # Disrupted vendor removed entirely — reorder rule effectively updated
                reorder_vendor_updated = True
            elif backup_info[0]['sequence'] <= precision_info[0]['sequence']:
                # Backup vendor has higher priority (lower sequence)
                reorder_vendor_updated = True

    result['products'][code] = {
        'found': True,
        'name': prod_name,
        'product_id': prod_id,
        'tmpl_id': tmpl_id,
        'current_qty': current_qty,
        'initial_qty': initial_state.get(code, {}).get('qty', 0),
        'all_pos': po_details,
        'cancelled_precision_pos': cancelled_precision_pos,
        'active_precision_pos': active_precision_pos,
        'new_backup_confirmed_pos': new_backup_pos,
        'new_backup_draft_pos': new_backup_draft_pos,
        'has_correct_backup_po': has_correct_backup_po,
        'backup_po_qty': backup_po_qty,
        'expected_backup_vendor_id': expected_backup_id,
        'has_reorder_rule': has_reorder_rule,
        'reorder_vendor_updated': reorder_vendor_updated,
        'initial_pos': initial_state.get(code, {}).get('pos', []),
    }

# Protected PO status (for anti-gaming)
protected_pos_status = {}
for code in protected_po_products:
    prod_data = result['products'].get(code, {})
    initial_pos = prod_data.get('initial_pos', [])
    current_pos = prod_data.get('all_pos', [])

    # Find the original confirmed PO
    original_confirmed = [p for p in initial_pos if p['state'] == 'purchase']
    current_confirmed = [p for p in current_pos if p['state'] == 'purchase']

    # Check if the original confirmed PO is still intact
    original_po_ids = {p['po_id'] for p in original_confirmed}
    current_po_ids = {p['po_id'] for p in current_confirmed}
    still_intact = original_po_ids.issubset(current_po_ids)

    # Also check if any original PO was cancelled
    all_current = {p['po_id']: p['state'] for p in current_pos}
    any_cancelled = any(all_current.get(po_id) == 'cancel' for po_id in original_po_ids)

    protected_pos_status[code] = {
        'original_po_ids': list(original_po_ids),
        'still_intact': still_intact,
        'any_cancelled': any_cancelled,
    }

result['protected_pos_status'] = protected_pos_status

with open('/tmp/vendor_disruption_pivot_result.json', 'w') as f:
    json.dump(result, f, indent=2)
os.chmod('/tmp/vendor_disruption_pivot_result.json', 0o666)

print("Export complete.")
print(json.dumps(result, indent=2))
PYEOF
