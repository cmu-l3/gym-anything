#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << PYEOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'
task_start = ${TASK_START}

result = {
    'task_start': task_start,
    'error': None,
    'wh_stock_loc_id': None,
    'is_multi_loc_enabled': False,
    'zones': {},
    'products': {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # Check multi-locations setting
    result['is_multi_loc_enabled'] = execute('res.users', 'has_group', ['stock.group_stock_multi_locations'])

    # Get WH/Stock
    wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
    if wh:
        wh_stock_loc_id = wh[0]['lot_stock_id'][0]
        result['wh_stock_loc_id'] = wh_stock_loc_id

        # Get zones
        zones = execute('stock.location', 'search_read', 
                        [[('name', 'in', ['Zone A', 'Zone B', 'Zone C']), ('active', '=', True)]], 
                        fields=['name', 'location_id', 'cyclic_inventory_frequency'])
        
        for z in zones:
            result['zones'][z['name']] = {
                'id': z['id'],
                'parent_id': z['location_id'][0] if z.get('location_id') else None,
                'frequency': z.get('cyclic_inventory_frequency', 0)
            }

        # Get product stock
        codes = ['ABC-A-001', 'ABC-B-001', 'ABC-C-001']
        for code in codes:
            prod = execute('product.product', 'search_read', [[('default_code', '=', code)]], fields=['id'], limit=1)
            if prod:
                quants = execute('stock.quant', 'search_read', [[('product_id', '=', prod[0]['id'])]], fields=['location_id', 'quantity'])
                # Filter > 0
                active_quants = []
                for q in quants:
                    if q['quantity'] > 0:
                        active_quants.append({
                            'loc_id': q['location_id'][0] if q.get('location_id') else None,
                            'loc_name': q['location_id'][1] if q.get('location_id') else None,
                            'qty': q['quantity']
                        })
                result['products'][code] = active_quants

except Exception as e:
    result['error'] = str(e)

with open('/tmp/abc_cycle_counting_locations_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF