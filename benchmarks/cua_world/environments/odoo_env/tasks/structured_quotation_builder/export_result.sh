#!/bin/bash
# Export script for structured_quotation_builder task

echo "=== Exporting Structured Quotation Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract data from Odoo
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    # If connection fails, write error to JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'success': False}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Load setup info to get correct customer ID
try:
    with open('/tmp/structured_quotation_setup.json', 'r') as f:
        setup_info = json.load(f)
        customer_id = setup_info['customer_id']
except:
    customer_id = None

result = {
    'quotation_found': False,
    'lines': [],
    'meta': {},
    'task_timestamp': datetime.datetime.now().isoformat()
}

if customer_id:
    # Find most recent quotation for this customer
    # State should ideally be draft or sent
    orders = execute('sale.order', 'search_read', 
        [[['partner_id', '=', customer_id]]], 
        {'fields': ['id', 'name', 'state', 'validity_date', 'amount_total', 'create_date'], 'order': 'id desc', 'limit': 1})

    if orders:
        order = orders[0]
        result['quotation_found'] = True
        result['meta'] = {
            'id': order['id'],
            'name': order['name'],
            'state': order['state'],
            'validity_date': order['validity_date'],
            'amount_total': order['amount_total'],
            'create_date': order['create_date']
        }

        # Fetch order lines
        lines = execute('sale.order.line', 'search_read',
            [[['order_id', '=', order['id']]]],
            {'fields': ['sequence', 'display_type', 'name', 'product_id', 'product_uom_qty', 'price_unit'], 'order': 'sequence asc'})
        
        # Clean up line data for export
        clean_lines = []
        for line in lines:
            clean_lines.append({
                'sequence': line['sequence'],
                'display_type': line['display_type'], # False/None (product), 'line_section', 'line_note'
                'name': line['name'],
                'product_name': line['product_id'][1] if line['product_id'] else None,
                'qty': line['product_uom_qty'],
                'price': line['price_unit']
            })
        result['lines'] = clean_lines

# Write result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result saved to /tmp/task_result.json")
PYEOF

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Done ==="