#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/serial_traceability_final.png" || true

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

# Get the product
product = execute('product.product', 'search_read', 
                  [[['default_code', '=', 'MED-CM-PRO']]], 
                  fields=['id'], limit=1)
product_id = product[0]['id'] if product else None

# Identify Quarantine locations (any internal location with "Quarantine" in the name)
quarantine_locs = execute('stock.location', 'search_read',
                          [[['name', 'ilike', 'Quarantine'], ['usage', '=', 'internal']]],
                          fields=['id', 'name'])
quarantine_loc_ids = [loc['id'] for loc in quarantine_locs]

# Identify stock locations (WH/Stock)
wh = execute('stock.warehouse', 'search_read', [[]], fields=['id', 'lot_stock_id'], limit=1)
stock_loc_id = wh[0]['lot_stock_id'][0] if wh else None

# Check locations for each specific serial number
serials_to_check = ['CM-2024-089', 'CM-2024-090', 'CM-2024-091', 'CM-2024-092', 'CM-2024-093', 'CM-2024-094', 'CM-2024-095']

sn_locations = {}

if product_id:
    for sn in serials_to_check:
        lot = execute('stock.lot', 'search_read', 
                      [[['name', '=', sn], ['product_id', '=', product_id]]], 
                      fields=['id'], limit=1)
        if lot:
            lot_id = lot[0]['id']
            # Find positive quants for this lot
            quants = execute('stock.quant', 'search_read',
                             [[['lot_id', '=', lot_id], ['quantity', '>', 0]]],
                             fields=['location_id', 'quantity'])
            if quants:
                loc_id = quants[0]['location_id'][0]
                loc_name = quants[0]['location_id'][1]
                
                is_quarantine = loc_id in quarantine_loc_ids
                is_stock = loc_id == stock_loc_id
                
                sn_locations[sn] = {
                    'loc_id': loc_id,
                    'loc_name': loc_name,
                    'is_quarantine': is_quarantine,
                    'is_stock': is_stock
                }
            else:
                sn_locations[sn] = {'loc_id': None, 'loc_name': 'Consumed/None', 'is_quarantine': False, 'is_stock': False}
        else:
            sn_locations[sn] = {'loc_id': None, 'loc_name': 'Not Found', 'is_quarantine': False, 'is_stock': False}

result = {
    'task_start': task_start,
    'quarantine_locations_exist': len(quarantine_locs) > 0,
    'quarantine_locations': quarantine_locs,
    'stock_loc_id': stock_loc_id,
    'product_found': product_id is not None,
    'sn_locations': sn_locations
}

with open('/tmp/serial_traceability_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
os.chmod('/tmp/serial_traceability_result.json', 0o666)

print("Export complete.")
print(json.dumps(result, indent=2, default=str))
PYEOF