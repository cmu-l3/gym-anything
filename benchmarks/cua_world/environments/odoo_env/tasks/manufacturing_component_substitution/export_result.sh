#!/bin/bash
# Export script for manufacturing_component_substitution
# Queries Odoo to check if the Manufacturing Order was created, modified correctly, and completed.

echo "=== Exporting manufacturing results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ ! -f /tmp/mrp_sub_setup.json ]; then
    echo "ERROR: Setup data not found"
    echo '{"error": "setup_data_missing"}' > /tmp/mrp_sub_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup data
with open('/tmp/mrp_sub_setup.json') as f:
    setup = json.load(f)

# Load task start timestamp
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/mrp_sub_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

products = setup['products']
pump_id = products['Centrifugal Pump CP-200']
standard_gasket_id = products['Standard Gasket G-100']
premium_gasket_id = products['Premium Gasket G-200']
bom_id = setup['bom_id']

# 1. Find the Manufacturing Order
# Look for MOs created for the pump, sorted by ID desc
mos = execute('mrp.production', 'search_read', 
    [[['product_id', '=', pump_id]]], 
    {'fields': ['id', 'name', 'state', 'date_start', 'move_raw_ids'], 'order': 'id desc', 'limit': 1})

mo_found = False
mo_data = {}
consumed_products = []

if mos:
    mo = mos[0]
    # Simple check: assuming ID is higher than what existed before (not strictly checked here but implied by 'new')
    mo_found = True
    
    # Get the raw moves (consumed components)
    move_ids = mo['move_raw_ids']
    if move_ids:
        moves = execute('stock.move', 'read', [move_ids], {'fields': ['product_id', 'state', 'quantity', 'quantity_done']}) # quantity_done in Odoo 15+, 'quantity' or 'product_uom_qty' elsewhere
        
        for m in moves:
            # product_id is [id, name]
            pid = m['product_id'][0]
            # Check if move is done or cancel
            state = m['state']
            # In Odoo, substitutions often result in the original line being cancelled or having 0 done qty,
            # and a new line being added.
            
            # We care about what was effectively consumed (state='done' or quantity_done > 0)
            qty_done = m.get('quantity_done', 0) or m.get('quantity', 0) # Fallback depending on version
            
            if state == 'done' and qty_done > 0:
                consumed_products.append(pid)

    mo_data = {
        'id': mo['id'],
        'state': mo['state'],
        'consumed_product_ids': consumed_products
    }

# 2. Check Master BOM Integrity
# Ensure Standard Gasket is still there and Premium is NOT
bom_lines = execute('mrp.bom.line', 'search_read',
    [[['bom_id', '=', bom_id]]],
    {'fields': ['product_id']})

bom_product_ids = [l['product_id'][0] for l in bom_lines]

result = {
    'mo_found': mo_found,
    'mo_data': mo_data,
    'bom_product_ids': bom_product_ids,
    'target_ids': {
        'standard_gasket': standard_gasket_id,
        'premium_gasket': premium_gasket_id
    }
}

with open('/tmp/mrp_sub_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "=== Export complete ==="