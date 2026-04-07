#!/bin/bash
# Export script for product_packaging_hierarchy_sales task
# Exports the state of product packagings and the customer's sales order.

echo "=== Exporting product_packaging_hierarchy_sales Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to query Odoo via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect to Odoo: {e}'}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

result = {
    'task_start': 0,
    'feature_enabled': False,
    'retail_pack_found': False,
    'master_case_found': False,
    'sales_order_found': False,
    'sales_order_confirmed': False,
    'sales_order_total_qty': 0.0,
    'sales_order_name': ''
}

# 1. Check if Feature is Enabled (user has the group)
try:
    user_groups = execute('res.users', 'read', [uid], {'fields': ['groups_id']})[0]['groups_id']
    packaging_groups = execute('res.groups', 'search', [[['name', 'ilike', 'packaging']]])
    # If intersection is not empty, feature is enabled
    if set(packaging_groups).intersection(set(user_groups)):
        result['feature_enabled'] = True
except Exception as e:
    print(f"Error checking feature: {e}")

# 2. Check Packaging Definitions
try:
    product = execute('product.product', 'search_read', [[['name', '=', 'Bamboo Fiber Bento Box']]], {'fields': ['id', 'product_tmpl_id'], 'limit': 1})
    if product:
        product_id = product[0]['id']
        tmpl_id = product[0]['product_tmpl_id'][0]
        
        packagings = execute('product.packaging', 'search_read', 
                           [[['product_id', 'in', [product_id, False]]]], # Some packagings are linked to template or product
                           {'fields': ['name', 'qty', 'product_id']})
        
        # Filter for our specific product manually if needed, though search domain handles it usually
        # Actually packagings are linked to product.product usually.
        
        for p in packagings:
            # Check quantity matches expected
            if abs(p['qty'] - 12.0) < 0.1:
                result['retail_pack_found'] = True
            if abs(p['qty'] - 48.0) < 0.1:
                result['master_case_found'] = True
except Exception as e:
    print(f"Error checking packagings: {e}")

# 3. Check Sales Order
try:
    partner = execute('res.partner', 'search', [[['name', '=', 'GreenLife Retailers']]], {'limit': 1})
    if partner:
        orders = execute('sale.order', 'search_read', 
                       [[['partner_id', '=', partner[0]]]], 
                       {'fields': ['id', 'name', 'state', 'order_line'], 'order': 'id desc', 'limit': 1})
        
        if orders:
            order = orders[0]
            result['sales_order_found'] = True
            result['sales_order_name'] = order['name']
            if order['state'] in ['sale', 'done']:
                result['sales_order_confirmed'] = True
            
            # Calculate total qty for the specific product
            if product:
                product_id = product[0]['id']
                lines = execute('sale.order.line', 'read', [order['order_line']], {'fields': ['product_id', 'product_uom_qty']})
                total_qty = 0.0
                for line in lines:
                    if line['product_id'][0] == product_id:
                        total_qty += line['product_uom_qty']
                result['sales_order_total_qty'] = total_qty
except Exception as e:
    print(f"Error checking sales order: {e}")

# Add timestamp
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start'] = int(f.read().strip())
except:
    pass

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="