#!/bin/bash
# Export script for inventory_uom_procurement_flow
# Queries Odoo for UoM config, Product config, Stock levels, and POs

echo "=== Exporting inventory_uom_procurement_flow Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute Python export script
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    # Fail gracefully if Odoo is down
    result = {'error': str(e)}
    with open('/tmp/inventory_uom_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

result = {}

# 1. Check if UoM feature is enabled
# We check if the admin user is now in the group
uom_group_id = execute('res.groups', 'search', [[['name', '=', 'Units of Measure'], ['category_id.name', 'ilike', 'Inventory']]])
if uom_group_id:
    is_in_group = execute('res.users', 'search_count', [[['id', '=', uid], ['groups_id', 'in', uom_group_id]]])
    result['feature_enabled'] = (is_in_group > 0)
else:
    result['feature_enabled'] = False

# 2. Check "Case of 24" UoM configuration
uom_data = execute('uom.uom', 'search_read', 
    [[['name', '=', 'Case of 24']]], 
    {'fields': ['name', 'category_id', 'factor_inv', 'uom_type', 'active']})

if uom_data:
    uom = uom_data[0]
    result['uom_exists'] = True
    result['uom_name'] = uom['name']
    result['uom_ratio'] = uom['factor_inv'] # factor_inv is the ratio for "Bigger than reference"
    result['uom_type'] = uom['uom_type'] # bigger, smaller, reference
else:
    result['uom_exists'] = False

# 3. Check Product Configuration
product_data = execute('product.product', 'search_read',
    [[['name', '=', 'Glacier Spring Water 500ml']]],
    {'fields': ['id', 'name', 'uom_id', 'uom_po_id']})

if product_data:
    prod = product_data[0]
    result['product_exists'] = True
    result['product_uom_name'] = prod['uom_id'][1] if prod['uom_id'] else None
    result['product_po_uom_name'] = prod['uom_po_id'][1] if prod['uom_po_id'] else None
    product_id = prod['id']
else:
    result['product_exists'] = False
    product_id = None

# 4. Check Stock Quantity (Total on hand)
if product_id:
    quants = execute('stock.quant', 'search_read',
        [[['product_id', '=', product_id], ['location_id.usage', '=', 'internal']]],
        {'fields': ['quantity']})
    total_qty = sum(q['quantity'] for q in quants)
    result['stock_qty'] = total_qty
else:
    result['stock_qty'] = 0

# 5. Check Purchase Order
# Find POs for this product and vendor
if product_id:
    po_lines = execute('purchase.order.line', 'search_read',
        [[['product_id', '=', product_id], ['order_id.partner_id.name', '=', 'AquaPure Supplies'], ['state', 'in', ['purchase', 'done']]]],
        {'fields': ['product_qty', 'product_uom', 'order_id']})
    
    result['po_count'] = len(po_lines)
    if po_lines:
        line = po_lines[0]
        result['po_line_qty'] = line['product_qty']
        result['po_line_uom'] = line['product_uom'][1] if line['product_uom'] else None
else:
    result['po_count'] = 0

# 6. Anti-gaming: Check if stock move came from Vendors
if product_id:
    moves = execute('stock.move', 'search_read',
        [[['product_id', '=', product_id], ['state', '=', 'done'], ['location_id.usage', '=', 'supplier']]],
        {'fields': ['id', 'product_uom_qty', 'product_uom']})
    result['vendor_moves_count'] = len(moves)
else:
    result['vendor_moves_count'] = 0

# Save to file
with open('/tmp/inventory_uom_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Move result to safe location and set permissions
mv /tmp/inventory_uom_result.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="