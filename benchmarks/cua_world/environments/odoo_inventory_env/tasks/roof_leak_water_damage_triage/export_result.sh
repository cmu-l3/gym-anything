#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/roof_leak_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/roof_leak_final.png" || true

echo "Exporting state via XML-RPC..."
python3 << 'PYEOF'
import xmlrpc.client, json

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs or {})

all_codes = ['BLD-WP-001', 'BLD-WP-002', 'BLD-WP-003', 'BLD-VS-001', 'BLD-VS-002', 'BLD-VS-003']

stock_data = []
for code in all_codes:
    prod = execute('product.product', 'search_read', [[['default_code', '=', code]]], {'fields': ['id']})
    if prod:
        quants = execute('stock.quant', 'search_read', 
            [[['product_id', '=', prod[0]['id']], ['location_id.usage', '=', 'internal']]], 
            {'fields': ['location_id', 'quantity']})
        for q in quants:
            if q['quantity'] > 0:
                stock_data.append({
                    'code': code,
                    'location_name': q['location_id'][1],
                    'quantity': q['quantity']
                })

result = {'stock': stock_data}

with open('/tmp/roof_leak_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

chmod 666 /tmp/roof_leak_result.json