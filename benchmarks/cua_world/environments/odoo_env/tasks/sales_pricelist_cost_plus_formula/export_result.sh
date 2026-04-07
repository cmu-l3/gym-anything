#!/bin/bash
# Export script for sales_pricelist_cost_plus_formula

echo "=== Exporting pricelist task results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python export script
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup data
try:
    with open('/tmp/pricelist_setup.json') as f:
        setup = json.load(f)
except:
    setup = {}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Check for Pricelist "Wholesale Plus"
pricelist_name = "Wholesale Plus"
pricelists = execute('product.pricelist', 'search_read', 
    [[['name', '=', pricelist_name]]], 
    {'fields': ['id', 'name', 'item_ids']})

pricelist_found = False
pricelist_data = None
items_data = []

if pricelists:
    pricelist_found = True
    pricelist_data = pricelists[0]
    
    # Check items (rules)
    if pricelist_data['item_ids']:
        items = execute('product.pricelist.item', 'read', 
            [pricelist_data['item_ids']], 
            {'fields': ['compute_price', 'base', 'price_discount', 'price_surcharge', 'applied_on']})
        items_data = items

# 2. Check for Quotation for "Azure Interior" using this pricelist
order_found = False
order_data = None
line_data = None

if pricelist_found and setup.get('partner_id'):
    orders = execute('sale.order', 'search_read',
        [[['partner_id', '=', setup['partner_id']], ['pricelist_id', '=', pricelist_data['id']]]],
        {'fields': ['id', 'name', 'pricelist_id', 'order_line'], 'order': 'id desc', 'limit': 1})
    
    if orders:
        order_found = True
        order_data = orders[0]
        
        # Check order line for the specific product
        if order_data['order_line'] and setup.get('product_id'):
            lines = execute('sale.order.line', 'search_read',
                [[['order_id', '=', order_data['id']], ['product_id', '=', setup['product_id']]]],
                {'fields': ['price_unit', 'product_uom_qty']})
            
            if lines:
                line_data = lines[0]

result = {
    "setup": setup,
    "pricelist_found": pricelist_found,
    "pricelist": pricelist_data,
    "items": items_data,
    "order_found": order_found,
    "order": order_data,
    "line": line_data,
    "timestamp": os.popen("date +%s").read().strip()
}

with open('/tmp/pricelist_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/pricelist_result.json 2>/dev/null || true

cat /tmp/pricelist_result.json