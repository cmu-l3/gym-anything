#!/bin/bash

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fleet Vehicle Inventory Result ==="

TASK_START=$(cat /tmp/fleet_vehicle_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")
take_screenshot "/tmp/fleet_final.png" ga || true

python3 << PYEOF
import xmlrpc.client, json, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # Get Locations
    stock_locs = execute('stock.location', 'search_read', [[('name', '=', 'Stock')]], {'limit': 1, 'fields': ['id']})
    wh_stock_id = stock_locs[0]['id'] if stock_locs else None

    van_a_locs = execute('stock.location', 'search_read', [[('name', '=', 'Van A')]], {'limit': 1, 'fields': ['id']})
    van_a_id = van_a_locs[0]['id'] if van_a_locs else None

    # check inactive explicitly for Van B
    van_b_locs = execute('stock.location', 'search_read', [[('name', '=', 'Van B'), '|', ('active','=',True), ('active','=',False)]], {'limit': 1, 'fields': ['id', 'active']})
    van_b_id = van_b_locs[0]['id'] if van_b_locs else None
    van_b_active = van_b_locs[0]['active'] if van_b_locs else False

    # Get Van A Quants
    van_a_quants = []
    if van_a_id:
        van_a_q = execute('stock.quant', 'search_read', [[('location_id', '=', van_a_id), ('quantity', '>', 0)]], {'fields': ['product_id', 'quantity']})
        for q in van_a_q:
            prod_data = execute('product.product', 'read', [[q['product_id'][0]]], {'fields': ['default_code']})[0]
            van_a_quants.append({
                'code': prod_data['default_code'],
                'qty': q['quantity']
            })

    # Get Van B Quants
    van_b_quants = []
    if van_b_id:
        van_b_q = execute('stock.quant', 'search_read', [[('location_id', '=', van_b_id), ('quantity', '>', 0)]], {'fields': ['product_id', 'quantity']})
        for q in van_b_q:
            prod_data = execute('product.product', 'read', [[q['product_id'][0]]], {'fields': ['default_code']})[0]
            van_b_quants.append({
                'code': prod_data['default_code'],
                'qty': q['quantity']
            })

    # Check stock.picking for auditing (anti-gaming)
    pickings = execute('stock.picking', 'search_read', [[('state', '=', 'done')]], {'fields': ['location_id', 'location_dest_id']})
    transfer_to_a = False
    transfer_from_b = False

    for pick in pickings:
        src = pick['location_id'][0] if pick.get('location_id') else None
        dest = pick['location_dest_id'][0] if pick.get('location_dest_id') else None
        if src == wh_stock_id and dest == van_a_id:
            transfer_to_a = True
        if src == van_b_id and dest == wh_stock_id:
            transfer_from_b = True

    result = {
        'task_start': int(os.environ.get('TASK_START', '0')),
        'van_a_stock': van_a_quants,
        'van_b_stock': van_b_quants,
        'van_b_active': van_b_active,
        'used_transfer_to_a': transfer_to_a,
        'used_transfer_from_b': transfer_from_b
    }

    with open('/tmp/fleet_vehicle_result.json', 'w') as f:
        json.dump(result, f, indent=2)

    print("Export Complete.")
    print(json.dumps(result, indent=2))
except Exception as e:
    print(f"Export Error: {e}")
PYEOF

chmod 666 /tmp/fleet_vehicle_result.json 2>/dev/null || true
echo "=== End Export ==="