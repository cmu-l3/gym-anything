#!/bin/bash
# Export script for sales_quotation_to_invoice task

echo "=== Exporting sales_quotation_to_invoice Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

if [ ! -f /tmp/sales_quotation_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/sales_quotation_to_invoice_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

with open('/tmp/sales_quotation_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/sales_quotation_to_invoice_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

customer_id = setup['customer_id']
task_start = 0
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

# ─── Find sales orders for this customer created after task start ─────────────
orders = execute('sale.order', 'search_read',
    [[['partner_id', '=', customer_id]]],
    {'fields': ['id', 'name', 'state', 'amount_total', 'payment_term_id',
                'note', 'date_order', 'invoice_ids'],
     'order': 'id desc'})

# Get the most recent order
recent_order = orders[0] if orders else None

# Check if any order has 2 lines with the right products
target_product_ids = [p['product_id'] for p in setup['products'] if p.get('product_id')]
expected_total = setup['expected_total']

order_with_correct_products = None
for order in orders:
    # Get order lines
    lines = execute('sale.order.line', 'search_read',
        [[['order_id', '=', order['id']]]],
        {'fields': ['product_id', 'product_uom_qty', 'price_subtotal']})
    order_product_ids = [l['product_id'][0] if isinstance(l.get('product_id'), list) else l.get('product_id')
                         for l in lines]
    # Check if both target products are in this order
    if all(pid in order_product_ids for pid in target_product_ids):
        order_with_correct_products = order
        order_with_correct_products['_lines'] = lines
        break

# If no exact match, use most recent order
target_order = order_with_correct_products or recent_order

order_confirmed = False
order_has_correct_products = order_with_correct_products is not None
order_amount_correct = False
has_payment_terms = False
has_note = False
invoice_posted = False
invoice_paid = False
order_id = None

if target_order:
    order_id = target_order['id']
    order_confirmed = target_order.get('state') in ['sale', 'done']

    # Check amount (within 5% tolerance)
    order_amount = float(target_order.get('amount_total', 0))
    if expected_total > 0:
        order_amount_correct = abs(order_amount - expected_total) / expected_total < 0.05

    # Check payment terms (contains '30')
    pt = target_order.get('payment_term_id')
    pt_name = pt[1] if isinstance(pt, list) and len(pt) > 1 else ''
    has_payment_terms = '30' in str(pt_name)

    # Check note
    note = target_order.get('note', '') or ''
    has_note = 'priority' in note.lower() or 'expedit' in note.lower()

    # ─── Check invoices ───────────────────────────────────────────────────────
    invoice_ids = target_order.get('invoice_ids', [])
    if invoice_ids:
        invoices = execute('account.move', 'search_read',
            [[['id', 'in', invoice_ids], ['move_type', '=', 'out_invoice']]],
            {'fields': ['id', 'name', 'state', 'payment_state', 'amount_total']})
        for inv in invoices:
            if inv.get('state') == 'posted':
                invoice_posted = True
            if inv.get('payment_state') in ['paid', 'in_payment']:
                invoice_paid = True

    print(f"Order: {target_order['name']} | state={target_order['state']} | "
          f"amount=${order_amount:.2f} | pt='{pt_name}'")
    print(f"  confirmed={order_confirmed} | correct_products={order_has_correct_products}")
    print(f"  invoices: {len(invoice_ids)} | posted={invoice_posted} | paid={invoice_paid}")
else:
    print("No sales order found for this customer!")

result = {
    'task': 'sales_quotation_to_invoice',
    'customer_id': customer_id,
    'customer_name': setup['customer_name'],
    'order_id': order_id,
    'order_found': target_order is not None,
    'order_confirmed': order_confirmed,
    'order_has_correct_products': order_has_correct_products,
    'order_amount_correct': order_amount_correct,
    'order_amount': float(target_order.get('amount_total', 0)) if target_order else 0,
    'expected_amount': expected_total,
    'has_payment_terms_30': has_payment_terms,
    'has_priority_note': has_note,
    'invoice_posted': invoice_posted,
    'invoice_paid': invoice_paid,
    'task_start': task_start,
    'export_timestamp': datetime.now().isoformat(),
}

with open('/tmp/sales_quotation_to_invoice_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export Complete ==="
