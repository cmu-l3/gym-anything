#!/bin/bash
# Export script for manufacturing_serialized_scrap_workflow

echo "=== Exporting Manufacturing Scrap Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract data via Python XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

output = {
    'mo_state': None,
    'scrap_found': False,
    'scrap_lot': None,
    'consumed_lot': None,
    'produced_lot': None,
    'task_timestamp': 0
}

try:
    # Load timestamp
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            output['task_timestamp'] = int(f.read().strip())
    except:
        pass

    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    def execute(model, method, args=None, kwargs=None):
        return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

    # 1. Check MO State
    mo_search = execute('mrp.production', 'search_read', [[['name', '=', 'MO-00001']]], {'fields': ['id', 'state', 'lot_producing_id']})
    if mo_search:
        mo = mo_search[0]
        output['mo_state'] = mo['state']
        
        # Check produced Serial Number
        if mo.get('lot_producing_id'):
            lot = execute('stock.lot', 'read', [mo['lot_producing_id'][0]], {'fields': ['name']})
            if lot:
                output['produced_lot'] = lot[0]['name']

        # 2. Check for Scrap Record
        # Search for scrap associated with this MO's production_id or product
        scrap_search = execute('stock.scrap', 'search_read', 
            [[['production_id', '=', mo['id']]]], 
            {'fields': ['lot_id', 'product_id', 'state']}
        )
        
        # We look for a scrap record for LENS-A001
        for scrap in scrap_search:
            if scrap.get('lot_id'):
                lot_name = scrap['lot_id'][1]
                if 'LENS-A001' in lot_name:
                    output['scrap_found'] = True
                    output['scrap_lot'] = lot_name

        # 3. Check Consumed Components (Stock Moves)
        # We need to find which specific lot was actually consumed
        move_raw_ids = execute('stock.move', 'search_read', 
            [[['raw_material_production_id', '=', mo['id']], ['state', '=', 'done']]], 
            {'fields': ['id']}
        )
        
        move_ids = [m['id'] for m in move_raw_ids]
        if move_ids:
            # Check move lines for lot_id
            move_lines = execute('stock.move.line', 'search_read', 
                [[['move_id', 'in', move_ids]]], 
                {'fields': ['lot_id', 'qty_done', 'product_id']}
            )
            
            # We are looking for the 'Optical Lens Array' consumption
            for line in move_lines:
                # We assume the product name contains "Lens" or check ID if needed, but name is safer for generic check
                # Here we just look at the lot because lots are unique globally usually
                if line.get('lot_id'):
                    lot_name = line['lot_id'][1]
                    # We want to see if A002 was consumed
                    if 'LENS-A002' in lot_name and line['qty_done'] > 0:
                        output['consumed_lot'] = lot_name

except Exception as e:
    output['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f)
PYEOF

echo "Result saved to /tmp/task_result.json"