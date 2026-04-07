#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/configure_multistep_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/configure_multistep_final.png" || true

python3 << PYEOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

task_start = int(os.environ.get('TASK_START', '0'))

result = {
    'task_start': task_start,
    'warehouse': None,
    'pick_type': None,
    'pack_type': None,
    'locations': {}
}

try:
    with open('/tmp/initial_warehouse_state.json', 'r') as f:
        result['initial_state'] = json.load(f)
except Exception:
    result['initial_state'] = {}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
    
    whs = models.execute_kw(db, uid, password, 'stock.warehouse', 'search_read', [[['code', '=', 'WH']]], {
        'fields': ['id', 'reception_steps', 'delivery_steps', 'view_location_id', 
                   'pick_type_id', 'pack_type_id', 'wh_input_stock_loc_id', 
                   'wh_qc_stock_loc_id', 'wh_output_stock_loc_id', 'wh_pack_stock_loc_id']
    })
    
    if whs:
        wh = whs[0]
        result['warehouse'] = wh
        
        # Check Operation Types populated by Odoo upon setting 3-steps
        if wh.get('pick_type_id'):
            pick_type = models.execute_kw(db, uid, password, 'stock.picking.type', 'read', [[wh['pick_type_id'][0]]], {'fields': ['sequence_code', 'name']})
            result['pick_type'] = pick_type[0] if pick_type else None
            
        if wh.get('pack_type_id'):
            pack_type = models.execute_kw(db, uid, password, 'stock.picking.type', 'read', [[wh['pack_type_id'][0]]], {'fields': ['sequence_code', 'name']})
            result['pack_type'] = pack_type[0] if pack_type else None
            
        # Check Stock Locations populated by Odoo upon setting 3-steps
        loc_fields = {
            'input': 'wh_input_stock_loc_id',
            'qc': 'wh_qc_stock_loc_id',
            'output': 'wh_output_stock_loc_id',
            'packing': 'wh_pack_stock_loc_id'
        }
        
        for loc_key, loc_field in loc_fields.items():
            if wh.get(loc_field):
                loc = models.execute_kw(db, uid, password, 'stock.location', 'read', [[wh[loc_field][0]]], {'fields': ['name', 'active', 'complete_name']})
                result['locations'][loc_key] = loc[0] if loc else None

except Exception as e:
    result['error'] = str(e)

with open('/tmp/configure_multistep_result.json', 'w') as f:
    json.dump(result, f, indent=2)

os.chmod('/tmp/configure_multistep_result.json', 0o666)
print(json.dumps(result, indent=2))
PYEOF