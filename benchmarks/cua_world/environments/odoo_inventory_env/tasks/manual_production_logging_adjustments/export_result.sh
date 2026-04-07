#!/bin/bash
# Export script for manual_production_logging_adjustments

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")
RESULT_FILE="/tmp/manual_production_result.json"

take_screenshot "/tmp/task_end.png" ga || true

# Extract final data via XML-RPC
python3 << PYEOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
username = 'admin'
password = 'admin'
task_start = int('$TASK_START')

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs or {})

# Get warehouse stock location
wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
stock_loc_id = wh[0]['lot_stock_id'][0]

lots_to_check = ['PP-1001', 'PP-1002', 'DYE-BLU-77', 'DYE-RED-42', 'DYE-YEL-19', 'PB-BLU-4099']

result = {
    'task_start': task_start,
    'lots': {},
    'adjustments_made': []
}

for lot_name in lots_to_check:
    # Find the lot
    lot_records = execute('stock.lot', 'search_read', [[['name', '=', lot_name]]], {'fields': ['id', 'product_id']})
    
    if not lot_records:
        result['lots'][lot_name] = {'found': False, 'qty': 0}
        continue
        
    lot_id = lot_records[0]['id']
    product_id = lot_records[0]['product_id'][0]
    
    # Get quant in WH/Stock
    quants = execute('stock.quant', 'search_read', [[
        ['lot_id', '=', lot_id], 
        ['location_id', '=', stock_loc_id]
    ]], {'fields': ['quantity']})
    
    qty = sum(q['quantity'] for q in quants)
    
    # Check if a stock move line was created for this product/lot after task start
    # indicating an adjustment happened
    moves = execute('stock.move.line', 'search_read', [[
        ['lot_id', '=', lot_id],
        ['product_id', '=', product_id]
    ]], {'fields': ['id', 'create_date', 'qty_done']})
    
    # Odoo create_date is string UTC 'YYYY-MM-DD HH:MM:SS'
    moves_after_start = 0
    import datetime
    for m in moves:
        if m['create_date']:
            try:
                dt = datetime.datetime.strptime(m['create_date'], '%Y-%m-%d %H:%M:%S')
                # Odoo DB time is UTC. Compare to local task_start approx
                # We'll just check if it's broadly recent. Since docker might have different timezone, 
                # let's be generous or just record the fact there are multiple moves.
                # Actually, any new move since our initial setup script is an indication.
                # We can just count total moves and assume >1 means the user interacted with it, 
                # since setup creates exactly 1 initial inventory move (the apply action).
                pass
            except:
                pass
                
    result['lots'][lot_name] = {
        'found': True,
        'qty': qty,
        'moves_count': len(moves)
    }

# Find all stock.move.lines created recently just to audit agent actions
all_recent_moves = execute('stock.move.line', 'search_read', [], {'fields': ['id', 'product_id', 'lot_id', 'qty_done', 'location_id', 'location_dest_id'], 'order': 'id desc', 'limit': 20})
result['recent_moves'] = all_recent_moves

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)

os.chmod('$RESULT_FILE', 0o666)
PYEOF

echo "Export complete. Result saved to $RESULT_FILE"
cat $RESULT_FILE