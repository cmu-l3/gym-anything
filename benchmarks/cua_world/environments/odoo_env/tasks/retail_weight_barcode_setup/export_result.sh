#!/bin/bash
# Export script for retail_weight_barcode_setup
# Extracts barcode rules and product configuration to JSON

echo "=== Exporting retail_weight_barcode_setup Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Run Python export script
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

output = {
    "task_start": 0,
    "task_end": 0,
    "rules": [],
    "product": None,
    "error": None
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        output['task_start'] = int(f.read().strip())
    output['task_end'] = int(datetime.datetime.now().timestamp())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    def execute(model, method, args=None, kwargs=None):
        return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

    # 1. Inspect Barcode Rules
    # Search for rules that might match the criteria (pattern starting with 24)
    # or just get all weighted rules to be safe
    rules_data = execute('barcode.rule', 'search_read', 
        ['|', ['pattern', 'like', '24%'], ['type', '=', 'weight']], 
        {'fields': ['name', 'pattern', 'type', 'encoding', 'sequence']})
    
    output['rules'] = rules_data

    # 2. Inspect Product
    # Search for product with barcode 55001 or name like 'Prosciutto'
    product_data = execute('product.product', 'search_read',
        ['|', ['barcode', '=', '55001'], ['name', 'ilike', 'Prosciutto']],
        {'fields': ['name', 'barcode', 'uom_id', 'lst_price', 'detailed_type']})
    
    if product_data:
        # Get UoM details for the first found product
        prod = product_data[0]
        if prod.get('uom_id'):
            uom_id = prod['uom_id'][0] if isinstance(prod['uom_id'], list) else prod['uom_id']
            uom_data = execute('uom.uom', 'read', [uom_id], {'fields': ['name']})
            if uom_data:
                prod['uom_name'] = uom_data[0]['name']
        output['product'] = prod

except Exception as e:
    output['error'] = str(e)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print("Export complete.")
PYEOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json