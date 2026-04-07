#!/bin/bash
# Export script for sales_phantom_kit_assembly
# Checks if the Kit BoM was created correctly and if the Delivery Order exploded the components.

echo "=== Exporting sales_phantom_kit_assembly Result ==="

# Record end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ ! -f /tmp/phantom_kit_setup.json ]; then
    echo "ERROR: Setup data missing"
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    with open('/tmp/phantom_kit_setup.json') as f:
        setup = json.load(f)
    task_start = int(open('/tmp/task_start_time.txt').read().strip())
except Exception as e:
    print(f"Error reading setup/time: {e}")
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

result = {
    'kit_product_created': False,
    'bom_created': False,
    'bom_type_is_kit': False,
    'bom_components_correct': False,
    'so_confirmed': False,
    'delivery_exists': False,
    'delivery_state_done': False,
    'delivery_moves_exploded': False
}

# 1. Find the Kit Product
kit_name = "Streamer Starter Kit"
products = execute('product.product', 'search_read', 
    [[['name', '=', kit_name]]], {'fields': ['id', 'name']})

kit_id = None
if products:
    result['kit_product_created'] = True
    kit_id = products[0]['id']

# 2. Check BoM
if kit_id:
    # Search for BoM associated with this product
    # Note: product_tmpl_id is usually used for BoMs, need to get template id
    prod_data = execute('product.product', 'read', [kit_id], {'fields': ['product_tmpl_id']})
    tmpl_id = prod_data[0]['product_tmpl_id'][0]
    
    boms = execute('mrp.bom', 'search_read', 
        [[['product_tmpl_id', '=', tmpl_id]]], 
        {'fields': ['id', 'type', 'bom_line_ids']})
    
    if boms:
        result['bom_created'] = True
        bom = boms[0]
        # Check type (phantom = Kit)
        if bom['type'] == 'phantom':
            result['bom_type_is_kit'] = True
        
        # Check components
        bom_lines = execute('mrp.bom.line', 'read', bom['bom_line_ids'], {'fields': ['product_id', 'product_qty']})
        bom_comp_ids = [l['product_id'][0] for l in bom_lines]
        setup_comp_ids = [c['id'] for c in setup['components']]
        
        # Check if all setup components are in the BoM
        if set(bom_comp_ids) == set(setup_comp_ids) and len(bom_comp_ids) == 3:
            result['bom_components_correct'] = True

# 3. Check Sales Order
# Find orders for this customer created after task start
orders = execute('sale.order', 'search_read',
    [[['partner_id', '=', setup['customer_id']]]], #, ['date_order', '>=', ...]] date comparison is tricky via xmlrpc sometimes
    {'fields': ['id', 'state', 'order_line', 'picking_ids'], 'order': 'id desc', 'limit': 1})

if orders:
    order = orders[0]
    # Verify it contains the kit
    lines = execute('sale.order.line', 'read', order['order_line'], {'fields': ['product_id']})
    product_ids = [l['product_id'][0] for l in lines]
    
    if kit_id and kit_id in product_ids:
        if order['state'] in ['sale', 'done']:
            result['so_confirmed'] = True
        
        # 4. Check Delivery (Picking)
        if order['picking_ids']:
            pickings = execute('stock.picking', 'read', order['picking_ids'], 
                {'fields': ['state', 'move_ids_without_package']})
            
            # Find the outgoing shipment
            picking = pickings[0] # Assuming simple flow
            result['delivery_exists'] = True
            if picking['state'] == 'done':
                result['delivery_state_done'] = True
            
            # 5. Check Stock Moves (The core check for Phantom Kits)
            # The moves should be for the COMPONENT products, NOT the Kit product
            move_ids = picking['move_ids_without_package']
            if move_ids:
                moves = execute('stock.move', 'read', move_ids, {'fields': ['product_id']})
                move_product_ids = [m['product_id'][0] for m in moves]
                
                setup_comp_ids = [c['id'] for c in setup['components']]
                
                # Check if moves match components exactly
                # (Allowing for potential partial availability, but checking key set)
                if set(move_product_ids) == set(setup_comp_ids):
                    result['delivery_moves_exploded'] = True
                elif kit_id in move_product_ids:
                    # If the kit product is in the moves, it didn't explode
                    result['delivery_moves_exploded'] = False

# Save Result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="