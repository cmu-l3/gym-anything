#!/bin/bash
# Export script for Janitorial SKU Consolidation

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="
take_screenshot /tmp/janitorial_cleanup_final.png || true

TASK_START=$(cat /tmp/janitorial_cleanup_task_start 2>/dev/null || echo "0")

python3 << PYEOF
import xmlrpc.client
import json
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
username = 'admin'
password = 'admin'

result = {
    'task_start': int("$TASK_START"),
    'products': {},
    'error': None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    # Get warehouse stock location
    wh = models.execute_kw(db, uid, password, 'stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
    loc_id = wh[0]['lot_stock_id'][0]

    all_codes = [
        "JAN-001", "JAN-002", "JAN-003", 
        "JAN-001-DUP", "JAN-002-DUP", "JAN-003-DUP",
        "JAN-004", "JAN-005", "JAN-006", "JAN-007"
    ]

    for code in all_codes:
        # Search including archived products
        tmpl = models.execute_kw(db, uid, password, 'product.template', 'search_read', 
                                 [[['default_code', '=', code], ['active', 'in', [True, False]]]], 
                                 {'fields': ['id', 'name', 'active', 'product_variant_ids'], 'limit': 1})
        
        if not tmpl:
            result['products'][code] = {'found': False}
            continue

        tmpl_data = tmpl[0]
        prod_id = tmpl_data['product_variant_ids'][0]

        # Get stock quants for this specific location
        quants = models.execute_kw(db, uid, password, 'stock.quant', 'search_read', 
                                   [[['product_id', '=', prod_id], ['location_id', '=', loc_id]]], 
                                   {'fields': ['quantity']})
        
        current_qty = sum(q['quantity'] for q in quants)

        result['products'][code] = {
            'found': True,
            'active': tmpl_data['active'],
            'name': tmpl_data['name'],
            'qty': current_qty
        }

except Exception as e:
    result['error'] = str(e)

# Save the result securely
output_path = '/tmp/janitorial_cleanup_result.json'
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

os.chmod(output_path, 0o666)
print(f"Results exported to {output_path}")
PYEOF

echo "=== Export Complete ==="