#!/bin/bash

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/bulk_import_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/bulk_import_final.png" || true

python3 << PYEOF
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'
task_start = int(os.environ.get('TASK_START', '0'))

try:
    with open('/tmp/bulk_import_initial_state.json') as f:
        initial_state = json.load(f)
except Exception:
    initial_state = {'total_products': 0, 'category_id': None}

result = {
    'task_start': task_start,
    'initial_products_count': initial_state.get('total_products', 0),
    'electronics_category_id': initial_state.get('category_id'),
    'current_products_count': 0,
    'products_found_by_sku': {},
    'products_found_by_name': {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    if not uid:
        raise Exception("Authentication failed")
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # Get current total products
    result['current_products_count'] = execute('product.template', 'search_count', [[]])

    elec_skus = [f"ELEC-{i:03d}" for i in range(1, 13)]
    
    # Check by SKU
    products_by_sku = execute('product.template', 'search_read', 
        [[['default_code', 'in', elec_skus]]], 
        fields=['id', 'name', 'default_code', 'list_price', 'standard_price', 'categ_id', 'type', 'weight', 'create_date'])
        
    for p in products_by_sku:
        sku = p.get('default_code')
        if sku:
            result['products_found_by_sku'][sku] = p

    # In case they mapped Name but messed up SKU mapping, search by partial name
    all_names = [
        "Anker PowerCore 10000mAh Portable Charger", "Logitech M720 Triathlon Multi-Device Mouse", 
        "SanDisk Ultra 128GB microSDXC UHS-I Card", "JBL Tune 510BT Wireless On-Ear Headphones", 
        "Samsung T7 Portable SSD 500GB", "TP-Link Archer T3U AC1300 USB WiFi Adapter", 
        "Corsair K55 RGB Pro Gaming Keyboard", "Logitech C920 HD Pro Webcam 1080p", 
        "WD Elements 2TB Portable External HDD", "Anker 735 Charger GaNPrime 65W", 
        "HyperX Cloud Stinger 2 Gaming Headset", "Razer DeathAdder Essential Gaming Mouse"
    ]
    
    products_by_name = execute('product.template', 'search_read', 
        [[['name', 'in', all_names]]], 
        fields=['id', 'name', 'default_code', 'list_price', 'standard_price', 'categ_id', 'type', 'weight', 'create_date'])
        
    for p in products_by_name:
        name = p.get('name')
        if name:
            result['products_found_by_name'][name] = p

except Exception as e:
    result['error'] = str(e)

with open('/tmp/bulk_import_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
os.chmod('/tmp/bulk_import_result.json', 0o666)

print("Export complete.")
PYEOF