#!/bin/bash
# Export script for make_to_order_fulfillment_cycle
# Queries all cross-module state: Sales Order, Manufacturing Order,
# Purchase Order, Receipts, Deliveries, Invoice, and Payment status.

echo "=== Exporting make_to_order_fulfillment_cycle results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check setup data exists
if [ ! -f /tmp/mto_fulfillment_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || true
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin'
PASSWORD = 'admin'

# Load setup data
with open('/tmp/mto_fulfillment_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/mto_fulfillment_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

result = {
    'task': 'make_to_order_fulfillment_cycle',
    'export_timestamp': datetime.now().isoformat(),
}

customer_id = setup['customer_id']
vendor_id = setup['vendor_id']
fp_product_id = setup['finished_product_id']
fp_tmpl_id = setup['finished_product_tmpl_id']

# ─── 1. Sales Order ──────────────────────────────────────────────────────────
orders = execute('sale.order', 'search_read',
    [[['partner_id', '=', customer_id]]],
    {'fields': ['id', 'name', 'state', 'amount_total', 'amount_untaxed',
                'invoice_ids', 'picking_ids', 'date_order'],
     'order': 'id desc'})

target_so = None
so_lines = []

for order in orders:
    lines = execute('sale.order.line', 'search_read',
        [[['order_id', '=', order['id']]]],
        {'fields': ['product_id', 'product_uom_qty', 'price_unit', 'price_subtotal']})
    # Check if this order has the camera product
    for line in lines:
        pid = line['product_id'][0] if isinstance(line.get('product_id'), list) else line.get('product_id')
        if pid == fp_product_id:
            target_so = order
            so_lines = lines
            break
    if target_so:
        break

if target_so:
    result['sales_order'] = {
        'found': True,
        'id': target_so['id'],
        'name': target_so['name'],
        'state': target_so['state'],
        'amount_total': target_so['amount_total'],
        'amount_untaxed': target_so['amount_untaxed'],
        'invoice_ids': target_so.get('invoice_ids', []),
        'picking_ids': target_so.get('picking_ids', []),
        'lines': [{
            'product_name': l['product_id'][1] if isinstance(l.get('product_id'), list) else '',
            'product_id': l['product_id'][0] if isinstance(l.get('product_id'), list) else l.get('product_id'),
            'qty': l['product_uom_qty'],
            'price_unit': l['price_unit'],
            'price_subtotal': l['price_subtotal'],
        } for l in so_lines],
    }
    print(f"Found SO: {target_so['name']} state={target_so['state']} total={target_so['amount_total']}")
else:
    result['sales_order'] = {'found': False}
    print("No sales order found for customer.")

# ─── 2. Manufacturing Order ──────────────────────────────────────────────────
mos = execute('mrp.production', 'search_read',
    [[['product_id', '=', fp_product_id]]],
    {'fields': ['id', 'name', 'state', 'product_qty', 'date_start',
                'move_raw_ids', 'bom_id'],
     'order': 'id desc'})

target_mo = mos[0] if mos else None
mo_components = []

if target_mo:
    # Get consumed components (raw material moves)
    if target_mo.get('move_raw_ids'):
        raw_moves = execute('stock.move', 'read',
            [target_mo['move_raw_ids']],
            {'fields': ['product_id', 'product_uom_qty', 'quantity', 'state']})
        # In Odoo 17, 'quantity' is the done quantity for completed moves
        for move in raw_moves:
            mo_components.append({
                'product_name': move['product_id'][1] if isinstance(move.get('product_id'), list) else '',
                'product_id': move['product_id'][0] if isinstance(move.get('product_id'), list) else move.get('product_id'),
                'qty_demanded': move['product_uom_qty'],
                'qty_done': move.get('quantity', 0),
                'state': move['state'],
            })

    result['manufacturing_order'] = {
        'found': True,
        'id': target_mo['id'],
        'name': target_mo['name'],
        'state': target_mo['state'],
        'product_qty': target_mo['product_qty'],
        'components': mo_components,
    }
    print(f"Found MO: {target_mo['name']} state={target_mo['state']} qty={target_mo['product_qty']}")
else:
    result['manufacturing_order'] = {'found': False}
    print("No manufacturing order found.")

# ─── 3. Purchase Order ───────────────────────────────────────────────────────
pos = execute('purchase.order', 'search_read',
    [[['partner_id', '=', vendor_id]]],
    {'fields': ['id', 'name', 'state', 'amount_total', 'picking_ids', 'order_line'],
     'order': 'id desc'})

target_po = pos[0] if pos else None
po_lines = []

if target_po:
    if target_po.get('order_line'):
        lines = execute('purchase.order.line', 'read',
            [target_po['order_line']],
            {'fields': ['product_id', 'product_qty', 'price_unit', 'price_subtotal']})
        for line in lines:
            po_lines.append({
                'product_name': line['product_id'][1] if isinstance(line.get('product_id'), list) else '',
                'product_id': line['product_id'][0] if isinstance(line.get('product_id'), list) else line.get('product_id'),
                'qty': line['product_qty'],
                'price_unit': line['price_unit'],
                'price_subtotal': line['price_subtotal'],
            })

    # Check receipt status
    receipt_state = None
    if target_po.get('picking_ids'):
        pickings = execute('stock.picking', 'read',
            [target_po['picking_ids']],
            {'fields': ['state']})
        receipt_state = pickings[0]['state'] if pickings else None

    result['purchase_order'] = {
        'found': True,
        'id': target_po['id'],
        'name': target_po['name'],
        'state': target_po['state'],
        'amount_total': target_po['amount_total'],
        'lines': po_lines,
        'receipt_state': receipt_state,
    }
    print(f"Found PO: {target_po['name']} state={target_po['state']} receipt={receipt_state}")
else:
    result['purchase_order'] = {'found': False}
    print("No purchase order found for vendor.")

# ─── 4. Delivery (from SO) ───────────────────────────────────────────────────
if target_so and target_so.get('picking_ids'):
    pickings = execute('stock.picking', 'search_read',
        [[['id', 'in', target_so['picking_ids']]]],
        {'fields': ['id', 'name', 'state', 'picking_type_id', 'move_ids']})

    delivery_info = []
    for picking in pickings:
        move_details = []
        if picking.get('move_ids'):
            moves = execute('stock.move', 'read',
                [picking['move_ids']],
                {'fields': ['product_id', 'product_uom_qty', 'quantity', 'state']})
            for m in moves:
                move_details.append({
                    'product_name': m['product_id'][1] if isinstance(m.get('product_id'), list) else '',
                    'qty_demanded': m['product_uom_qty'],
                    'qty_done': m.get('quantity', 0),
                    'state': m['state'],
                })
        delivery_info.append({
            'id': picking['id'],
            'name': picking['name'],
            'state': picking['state'],
            'moves': move_details,
        })

    any_done = any(p['state'] == 'done' for p in delivery_info)
    result['delivery'] = {
        'found': True,
        'any_done': any_done,
        'pickings': delivery_info,
    }
    print(f"Found {len(delivery_info)} delivery picking(s), any_done={any_done}")
else:
    result['delivery'] = {'found': False, 'any_done': False}
    print("No delivery pickings found.")

# ─── 5. Invoice and Payment ──────────────────────────────────────────────────
if target_so and target_so.get('invoice_ids'):
    invoices = execute('account.move', 'search_read',
        [[['id', 'in', target_so['invoice_ids']], ['move_type', '=', 'out_invoice']]],
        {'fields': ['id', 'name', 'state', 'amount_total', 'amount_residual',
                    'payment_state']})

    posted_invoices = [i for i in invoices if i['state'] == 'posted']
    paid_invoices = [i for i in invoices if i.get('payment_state') in ['paid', 'in_payment']]

    result['invoice'] = {
        'found': len(invoices) > 0,
        'count': len(invoices),
        'posted': len(posted_invoices) > 0,
        'posted_amount': sum(i['amount_total'] for i in posted_invoices),
        'paid': len(paid_invoices) > 0,
        'amount_residual': min((i['amount_residual'] for i in posted_invoices), default=None),
        'payment_state': posted_invoices[0].get('payment_state') if posted_invoices else None,
    }
    print(f"Found {len(invoices)} invoice(s), posted={len(posted_invoices)}, paid={len(paid_invoices)}")
else:
    result['invoice'] = {'found': False, 'posted': False, 'paid': False}
    print("No invoices found.")

# ─── 6. Anti-gaming: Check stock move origins ────────────────────────────────
# Verify cameras came from manufacturing (not manual stock adjustment)
camera_from_production = False
usbc_from_supplier = False
camera_to_customer = False

try:
    # Camera produced via manufacturing
    prod_moves = execute('stock.move', 'search_read',
        [[['product_id', '=', fp_product_id], ['state', '=', 'done'],
          ['location_id.usage', '=', 'production']]],
        {'fields': ['id', 'quantity'], 'limit': 5})
    camera_from_production = len(prod_moves) > 0

    # USB-C boards received from supplier
    usbc_prod_id = setup['component_product_ids'].get('USB-C Controller Board')
    if usbc_prod_id:
        supplier_moves = execute('stock.move', 'search_read',
            [[['product_id', '=', usbc_prod_id], ['state', '=', 'done'],
              ['location_id.usage', '=', 'supplier']]],
            {'fields': ['id', 'quantity'], 'limit': 5})
        usbc_from_supplier = len(supplier_moves) > 0

    # Camera shipped to customer
    customer_moves = execute('stock.move', 'search_read',
        [[['product_id', '=', fp_product_id], ['state', '=', 'done'],
          ['location_dest_id.usage', '=', 'customer']]],
        {'fields': ['id', 'quantity'], 'limit': 5})
    camera_to_customer = len(customer_moves) > 0
except Exception as e:
    print(f"Warning checking stock move origins: {e}")

result['anti_gaming'] = {
    'camera_from_production': camera_from_production,
    'usbc_from_supplier': usbc_from_supplier,
    'camera_to_customer': camera_to_customer,
}

# ─── Write Result ─────────────────────────────────────────────────────────────
with open('/tmp/mto_fulfillment_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

print("\nExport successful.")
PYEOF

# Copy to canonical location
cp /tmp/mto_fulfillment_result.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
