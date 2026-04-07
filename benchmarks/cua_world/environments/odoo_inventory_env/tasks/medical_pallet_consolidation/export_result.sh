#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/medical_pallet_final.png" || true

python3 << PYEOF
import xmlrpc.client
import json
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    task_start = int(os.environ.get('TASK_START', '0'))

    result = {
        'task_start': task_start,
        'packages_enabled': False,
        'rapid_deployment_loc_id': None,
        'quants': []
    }

    group = execute('ir.model.data', 'search_read', [[('module', '=', 'stock'), ('name', '=', 'group_tracking_lot')]], {'fields': ['res_id'], 'limit': 1})
    if group:
        group_id = group[0]['res_id']
        user_has_group = execute('res.users', 'search_count', [[('id', '=', uid), ('groups_id', 'in', [group_id])]])
        result['packages_enabled'] = user_has_group > 0

    wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
    if wh:
        stock_loc_id = wh[0]['lot_stock_id'][0]
        dep_locs = execute('stock.location', 'search_read', [[('name', '=', 'Rapid Deployment'), ('location_id', '=', stock_loc_id)]], {'fields': ['id'], 'limit': 1})
        if dep_locs:
            dep_loc_id = dep_locs[0]['id']
            result['rapid_deployment_loc_id'] = dep_loc_id
            
            quants = execute('stock.quant', 'search_read', [[('location_id', '=', dep_loc_id)]], {'fields': ['product_id', 'quantity', 'package_id']})
            
            for q in quants:
                result['quants'].append({
                    'product_id': q['product_id'][0] if q['product_id'] else None,
                    'product_name': q['product_id'][1] if q['product_id'] else None,
                    'quantity': q['quantity'],
                    'package_id': q['package_id'][0] if q['package_id'] else None,
                    'package_name': q['package_id'][1] if q['package_id'] else None
                })

    with open('/tmp/medical_pallet_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    os.chmod('/tmp/medical_pallet_result.json', 0o666)
except Exception as e:
    print(f"Error in export: {e}")
PYEOF