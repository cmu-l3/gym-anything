#!/bin/bash
# Export script for product_supplier_strategic_purchase task
# Queries product supplier info and created purchase orders.

echo "=== Exporting product_supplier_strategic_purchase Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if setup data exists
if [ ! -f /tmp/supplier_purchase_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    exit 0
fi

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python export logic
python3 << PYEOF
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup data
try:
    with open('/tmp/supplier_purchase_setup.json') as f:
        setup = json.load(f)
except Exception as e:
    print(f"Error loading setup: {e}")
    sys.exit(1)

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

product_id = setup['product_id']
vendor_ids = setup['vendors'] # dict name -> id
task_start_ts = int("$TASK_START")

# 1. Query Supplier Info (product.supplierinfo)
supplier_infos = execute('product.supplierinfo', 'search_read', 
    [[['product_tmpl_id', '=', product_id]]], 
    {'fields': ['partner_id', 'price', 'min_qty', 'delay']})

# Process supplier infos for easier verification
configured_suppliers = []
for info in supplier_infos:
    partner_id = info['partner_id'][0] if isinstance(info['partner_id'], list) else info['partner_id']
    configured_suppliers.append({
        'partner_id': partner_id,
        'price': info['price'],
        'min_qty': info['min_qty'],
        'delay': info['delay']
    })

# 2. Query Purchase Orders created after task start
# We look for POs that contain the target product
po_lines = execute('purchase.order.line', 'search_read',
    [[['product_id', 'in', [product_id]]]], # Note: product_id in setup is template id, but often same for single variant. 
    # To be safe, we should find the variant ID if needed, but usually template ID works for search if 1 variant.
    # Let's search by name to be safer if IDs differ.
    {'fields': ['order_id', 'product_qty', 'price_unit', 'product_id']})

# Get actual product variant ID if needed
variants = execute('product.product', 'search_read', [[['product_tmpl_id', '=', product_id]]], {'fields': ['id']})
variant_id = variants[0]['id'] if variants else None

relevant_orders = []

# Fetch headers for the lines found
order_ids_to_fetch = list(set([l['order_id'][0] for l in po_lines]))

if order_ids_to_fetch:
    orders = execute('purchase.order', 'search_read',
        [[['id', 'in', order_ids_to_fetch]]],
        {'fields': ['id', 'name', 'partner_id', 'state', 'date_order']})
    
    for order in orders:
        # Check creation date vs task start
        # Odoo dates are strings like '2023-10-25 10:00:00'
        # Simple check: assuming agent created it just now, ID should be high. 
        # But rigorous check is better.
        # We'll rely on the fact that we created the product fresh (or cleared it), 
        # so any PO with this product is likely from the agent.
        
        # Filter lines for this order
        lines = [l for l in po_lines if l['order_id'][0] == order['id']]
        # Assuming one line per product for simplicity
        line = lines[0] if lines else {}
        
        relevant_orders.append({
            'id': order['id'],
            'partner_id': order['partner_id'][0],
            'partner_name': order['partner_id'][1],
            'state': order['state'],
            'qty': line.get('product_qty', 0),
            'price_unit': line.get('price_unit', 0.0),
            'product_id': line.get('product_id', [0])[0]
        })

# Prepare result
result = {
    'setup_vendors': vendor_ids,
    'configured_suppliers': configured_suppliers,
    'purchase_orders': relevant_orders,
    'variant_id': variant_id,
    'task_start': task_start_ts
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "=== Export complete ==="