#!/bin/bash
# Export script for package_type_product_packaging task

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/package_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/package_type_final.png" || true

echo "Exporting database state via XML-RPC..."

python3 << PYEOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

task_start = int(os.environ.get('TASK_START', '0'))

result = {
    'task_start': task_start,
    'package_types': [],
    'product_packagings': [],
    'error': None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    
    if uid:
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
        def execute(model, method, args=None, **kwargs):
            return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

        # Retrieve package types
        pkg_types = execute('stock.package.type', 'search_read', [[]])
        result['package_types'] = pkg_types

        # Retrieve product packagings
        packagings = execute('product.packaging', 'search_read', [[]])
        for pkg in packagings:
            # Map the product ID to default_code for robust verification
            if pkg.get('product_id'):
                prod_id = pkg['product_id'][0]
                prod = execute('product.product', 'read', [[prod_id]], fields=['default_code'])
                if prod:
                    pkg['product_code'] = prod[0].get('default_code', '')
                    
            # Extract package type name cleanly
            if pkg.get('package_type_id'):
                pkg['package_type_name'] = pkg['package_type_id'][1]
                
        result['product_packagings'] = packagings

    else:
        result['error'] = "Authentication failed"

except Exception as e:
    result['error'] = str(e)

with open('/tmp/package_type_result.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2, default=str)

# Ensure verifier can read it
os.chmod('/tmp/package_type_result.json', 0o666)

print("Export complete.")
PYEOF

echo "=== Export Done ==="