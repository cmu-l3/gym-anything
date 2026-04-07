#!/bin/bash
# Export script for sales_down_payment_workflow task
# Queries the Sales Order and linked Invoices to verify the workflow.

echo "=== Exporting sales_down_payment_workflow Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

if [ ! -f /tmp/sales_down_payment_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/sales_down_payment_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

with open('/tmp/sales_down_payment_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/sales_down_payment_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

customer_id = setup['customer_id']
target_price = setup['target_price']

# 1. Find the Sales Order
# We look for the most recent one for this customer
orders = execute('sale.order', 'search_read',
    [[['partner_id', '=', customer_id]]],
    {'fields': ['id', 'name', 'state', 'amount_total', 'invoice_ids', 'order_line'], 'order': 'id desc', 'limit': 1})

so_found = False
so_data = {}
invoices_data = []

if orders:
    order = orders[0]
    so_found = True
    
    # Check order lines to ensure it's the right product
    lines = execute('sale.order.line', 'read', order['order_line'], {'fields': ['product_id', 'price_unit', 'product_uom_qty']})
    
    correct_product_line = False
    for line in lines:
        # Check price match (allow small tolerance)
        if abs(line['price_unit'] - target_price) < 1.0 and line['product_uom_qty'] >= 1:
            correct_product_line = True
            break
            
    so_data = {
        'id': order['id'],
        'name': order['name'],
        'state': order['state'],
        'amount_total': order['amount_total'],
        'correct_product_line': correct_product_line
    }

    # 2. Check Invoices
    if order['invoice_ids']:
        invoices = execute('account.move', 'read', order['invoice_ids'],
            {'fields': ['id', 'name', 'move_type', 'state', 'payment_state', 'amount_total', 'invoice_line_ids']})
        
        for inv in invoices:
            # Check lines for down payment product
            lines = execute('account.move.line', 'read', inv['invoice_line_ids'], {'fields': ['name', 'product_id', 'price_total', 'quantity']})
            
            is_down_payment = False
            has_negative_line = False
            
            for line in lines:
                line_name = line.get('name', '').lower()
                # Odoo standard down payment product usually has "Down Payment" in name or is specific service type
                if 'down payment' in line_name or 'deposit' in line_name:
                    if line['price_total'] > 0:
                        is_down_payment = True
                    elif line['price_total'] < 0:
                        has_negative_line = True
            
            invoices_data.append({
                'id': inv['id'],
                'state': inv['state'], # draft, posted
                'payment_state': inv['payment_state'], # not_paid, in_payment, paid
                'amount_total': inv['amount_total'],
                'is_down_payment': is_down_payment,
                'has_negative_line': has_negative_line
            })

result = {
    'task': 'sales_down_payment_workflow',
    'so_found': so_found,
    'so_data': so_data,
    'invoices': invoices_data,
    'setup_target_price': target_price,
    'export_timestamp': __import__('datetime').datetime.now().isoformat()
}

with open('/tmp/sales_down_payment_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Export complete."