#!/bin/bash
# Export script for inventory_internal_transfer
# Verify:
# 1. Transfer exists
# 2. Transfer state is Done
# 3. Correct Source/Dest
# 4. Correct Products/Quantities
# 5. Stock levels updated

echo "=== Exporting inventory_internal_transfer results ==="

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if setup file exists
if [ ! -f /tmp/transfer_setup.json ]; then
    echo "ERROR: Setup file missing!"
    echo '{"error": "setup_missing"}' > /tmp/task_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

# Helper for JSON serialization
def json_serial(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    with open('/tmp/transfer_setup.json', 'r') as f:
        setup = json.load(f)
except Exception as e:
    print(f"Error loading setup: {e}")
    sys.exit(1)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Load setup data
setup_prods = setup['products']
source_loc_id = setup['source_location_id']
dest_loc_id = setup['dest_location_id']

# 1. Find the transfer
# Look for internal transfers to the specific destination created recently
domain = [
    ['location_dest_id', '=', dest_loc_id],
    ['location_id', '=', source_loc_id],
    ['picking_type_code', '=', 'internal']
]
pickings = execute('stock.picking', 'search_read', [domain], 
    {'fields': ['id', 'name', 'state', 'origin', 'note', 'move_ids_without_package'], 'order': 'id desc', 'limit': 1})

result_data = {
    "transfer_found": False,
    "transfer_state": None,
    "reference_match": False,
    "source_loc_correct": False, # Verified by search domain implicitly, but we'll double check if needed
    "dest_loc_correct": False,
    "products_correct": False,
    "stock_levels_correct": False,
    "details": {}
}

if pickings:
    picking = pickings[0]
    result_data["transfer_found"] = True
    result_data["transfer_state"] = picking['state']
    
    # Check Reference (origin or note should contain QC-BATCH-2025-001)
    ref_target = "QC-BATCH-2025-001"
    note = picking.get('note') or ""
    origin = picking.get('origin') or ""
    if ref_target in note or ref_target in origin:
        result_data["reference_match"] = True
        
    result_data["source_loc_correct"] = True # By definition of search
    result_data["dest_loc_correct"] = True
    
    # Check move lines
    moves = execute('stock.move', 'read', [picking['move_ids_without_package']], {'fields': ['product_id', 'product_uom_qty', 'quantity']})
    
    correct_moves = 0
    for prod in setup_prods:
        target_qty = 20 if "Helmet" in prod['name'] else 30
        
        # Find move for this product
        # product_id is [id, name]
        move = next((m for m in moves if m['product_id'][0] == prod['id']), None)
        
        if move:
            # Check quantity (done quantity 'quantity' or demand 'product_uom_qty')
            # If done, 'quantity' should be set. If confirmed, 'product_uom_qty'
            qty_done = move.get('quantity', 0) # field is 'quantity' (Done) in Odoo 16/17, 'qty_done' in older
            if qty_done == 0:
                qty_done = move.get('product_uom_qty', 0) # Fallback if not validated yet
                
            if qty_done == target_qty:
                correct_moves += 1
    
    if correct_moves == 2:
        result_data["products_correct"] = True

# 2. Check Final Stock Levels (Independent of picking found)
stock_correct_count = 0
for prod in setup_prods:
    pid = prod['id']
    init_qty = prod['initial_qty']
    transfer_qty = 20 if "Helmet" in prod['name'] else 30
    
    # Check Source
    quants_src = execute('stock.quant', 'search_read', [[['product_id', '=', pid], ['location_id', '=', source_loc_id]]], {'fields': ['quantity']})
    curr_src = sum(q['quantity'] for q in quants_src)
    expected_src = init_qty - transfer_qty
    
    # Check Dest
    quants_dest = execute('stock.quant', 'search_read', [[['product_id', '=', pid], ['location_id', '=', dest_loc_id]]], {'fields': ['quantity']})
    curr_dest = sum(q['quantity'] for q in quants_dest)
    expected_dest = transfer_qty
    
    if abs(curr_src - expected_src) < 0.1 and abs(curr_dest - expected_dest) < 0.1:
        stock_correct_count += 1

if stock_correct_count == 2:
    result_data["stock_levels_correct"] = True

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, default=json_serial)

print("Export complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="