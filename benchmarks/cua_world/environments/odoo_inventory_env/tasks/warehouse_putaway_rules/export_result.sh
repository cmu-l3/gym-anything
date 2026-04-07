#!/bin/bash
# Export script for warehouse_putaway_rules
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
take_screenshot "/tmp/task_final.png" || true

python3 << PYEOF
import xmlrpc.client
import json
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

result = {
    'task_start': int(os.environ.get('TASK_START', '0')),
    'multi_loc_enabled': False,
    'locations': [],
    'putaway_rules': [],
    'wh_stock_id': None,
    'error': None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', password, {})
    if not uid:
        result['error'] = "Authentication failed"
    else:
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        def execute(*args, **kwargs):
            return models.execute_kw(db, uid, password, *args, **kwargs)

        # 1. Check if Storage Locations (multi-locations) is enabled for admin
        ir_model_data = execute('ir.model.data', 'search_read', 
            [[['module', '=', 'stock'], ['name', '=', 'group_stock_multi_locations']]], 
            {'fields': ['res_id']})
        
        if ir_model_data:
            group_id = ir_model_data[0]['res_id']
            user_data = execute('res.users', 'read', [[uid]], {'fields': ['groups_id']})
            result['multi_loc_enabled'] = group_id in user_data[0]['groups_id']

        # 2. Get WH/Stock ID
        wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
        if wh:
            result['wh_stock_id'] = wh[0]['lot_stock_id'][0]

        # 3. Get target locations
        loc_names = ['Zone A - Power Tools', 'Zone B - Hand Tools', 'Zone C - Fasteners']
        locations = execute('stock.location', 'search_read', 
            [[['name', 'in', loc_names]]], 
            {'fields': ['name', 'location_id', 'create_date']})
        result['locations'] = locations

        # 4. Get putaway rules
        rules = execute('stock.putaway.rule', 'search_read', [[]], 
            {'fields': ['category_id', 'location_in_id', 'location_out_id', 'create_date']})
        result['putaway_rules'] = rules

except Exception as e:
    result['error'] = str(e)

with open('/tmp/putaway_rules_result.json', 'w') as f:
    json.dump(result, f, indent=2)

os.chmod('/tmp/putaway_rules_result.json', 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/putaway_rules_result.json"
echo "=== Export complete ==="