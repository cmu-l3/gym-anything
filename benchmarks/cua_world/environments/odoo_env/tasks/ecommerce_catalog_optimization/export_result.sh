#!/bin/bash
# Export script for ecommerce_catalog_optimization

echo "=== Exporting eCommerce Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Odoo state
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
if not os.path.exists('/tmp/ecommerce_setup.json'):
    print("Setup file missing", file=sys.stderr)
    sys.exit(0)

with open('/tmp/ecommerce_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': str(e)}
    with open('/tmp/ecommerce_optimization_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Check Category
category = execute('product.public.category', 'search_read', 
    [[['name', 'ilike', 'Sustainable Workspace']]], 
    {'fields': ['id', 'name']})
category_id = category[0]['id'] if category else None

# Check Main Product (Bamboo Standing Desk)
main_product = execute('product.template', 'read', 
    [[setup['main_product_id']]], 
    {'fields': ['name', 'is_published', 'public_categ_ids', 'alternative_product_ids', 'accessory_product_ids', 'write_date']})[0]

# Check Draft Product (Recycled Paper Organizer)
draft_product = execute('product.template', 'read',
    [[setup['draft_product_id']]],
    {'fields': ['name', 'is_published', 'public_categ_ids', 'write_date']})[0]

result = {
    'setup': setup,
    'category_found': bool(category),
    'category_id': category_id,
    'main_product': {
        'is_published': main_product['is_published'],
        'category_ids': main_product['public_categ_ids'],
        'alternative_ids': main_product['alternative_product_ids'],
        'accessory_ids': main_product['accessory_product_ids'],
        'write_date': main_product['write_date']
    },
    'draft_product': {
        'is_published': draft_product['is_published'],
        'category_ids': draft_product['public_categ_ids'],
        'write_date': draft_product['write_date']
    }
}

with open('/tmp/ecommerce_optimization_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to allow safe copy
mv /tmp/ecommerce_optimization_result.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."