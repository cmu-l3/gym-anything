#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/scrap_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/scrap_final.png" || true

python3 << PYEOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

task_start = int(os.environ.get('TASK_START', '0'))

wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
if wh:
    stock_loc_id = wh[0]['lot_stock_id'][0]
else:
    stock_loc_id = False

all_codes = ['SCRAP-001', 'SCRAP-002', 'SCRAP-003', 'SCRAP-004', 'SCRAP-005', 'SCRAP-006']

result = {
    'task_start': task_start,
    'products': {}
}

for code in all_codes:
    tmpl = execute('product.template', 'search_read',
                   [[['default_code', '=', code]]],
                   fields=['id', 'name', 'product_variant_ids'], limit=1)
    if not tmpl:
        result['products'][code] = {'found': False}
        continue

    tmpl_id = tmpl[0]['id']
    prod_id = tmpl[0]['product_variant_ids'][0]
    prod_name = tmpl[0]['name']

    # Current stock quantity
    quants = execute('stock.quant', 'search_read',
                     [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]],
                     fields=['quantity'])
    current_qty = sum(q['quantity'] for q in quants)

    # Scrap records
    scraps = execute('stock.scrap', 'search_read',
                     [[['product_id', '=', prod_id]]],
                     fields=['name', 'scrap_qty', 'state', 'create_date'])
    
    total_scrapped_done = 0
    scraps_details = []
    
    for s in scraps:
        scraps_details.append({
            'name': s['name'],
            'qty': s['scrap_qty'],
            'state': s['state'],
            'create_date': s['create_date']
        })
        if s['state'] == 'done':
            total_scrapped_done += s['scrap_qty']

    result['products'][code] = {
        'found': True,
        'name': prod_name,
        'product_id': prod_id,
        'current_qty': current_qty,
        'total_scrapped_done': total_scrapped_done,
        'scraps': scraps_details
    }

with open('/tmp/scrap_task_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
os.chmod('/tmp/scrap_task_result.json', 0o666)

print("Export complete.")
PYEOF