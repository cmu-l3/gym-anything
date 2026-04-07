#!/bin/bash
# Export script for vendor_return_refund_workflow

echo "=== Exporting vendor_return_refund_workflow Result ==="

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check setup file
if [ ! -f /tmp/vendor_return_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    exit 0
fi

# Python script to query current state
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup
try:
    with open('/tmp/vendor_return_setup.json') as f:
        setup = json.load(f)
except Exception:
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': str(e)}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

vendor_id = setup['vendor_id']
product_id = setup['product_id']
task_start_time = 0
try:
    with open('/tmp/task_start_time.txt') as f:
        task_start_time = int(f.read().strip())
except:
    pass

# 1. Check for Return Picking (Outgoing to Vendor)
# Returns usually have location_dest_id as Vendor location (usage='supplier')
# and location_id as Internal.
# We look for pickings created AFTER task start (or just existence, as we didn't create returns in setup)
# Better: Look for pickings where partner is vendor, state is done, and it's a return.
pickings = execute('stock.picking', 'search_read',
    [[
        ['partner_id', '=', vendor_id],
        ['state', '=', 'done'],
        ['picking_type_code', 'in', ['outgoing', 'incoming']] # Returns can be incoming type if configured that way, but usually outgoing operation
    ]],
    {'fields': ['id', 'name', 'date_done', 'move_ids_without_package']})

return_found = False
return_qty = 0
return_date = ""

supplier_locs = execute('stock.location', 'search', [[['usage', '=', 'supplier']]])
supplier_loc_ids = supplier_locs

for p in pickings:
    # Check moves to verify it's a return (Dest is Supplier)
    moves = execute('stock.move', 'read', p['move_ids_without_package'], ['location_dest_id', 'product_id', 'quantity']) # quantity field varies by version
    
    for m in moves:
        # Check if destination is supplier
        dest_id = m['location_dest_id'][0]
        prod_id = m['product_id'][0]
        
        if dest_id in supplier_loc_ids and prod_id == product_id:
            # Check qty (Odoo 17 'quantity' or 'quantity_done')
            qty = m.get('quantity', 0)
            if qty == 0: qty = m.get('quantity_done', 0) # Fallback
            
            return_found = True
            return_qty += qty
            return_date = p['date_done']

# 2. Check for Credit Note (Refund)
# move_type = 'in_refund' for Vendor Credit Note
credit_notes = execute('account.move', 'search_read',
    [[
        ['partner_id', '=', vendor_id],
        ['move_type', '=', 'in_refund'],
        ['state', '=', 'posted']
    ]],
    {'fields': ['id', 'amount_total', 'invoice_date', 'invoice_line_ids']})

refund_found = False
refund_amount = 0.0

for cn in credit_notes:
    # Verify it contains the correct product
    lines = execute('account.move.line', 'read', cn['invoice_line_ids'], ['product_id'])
    has_product = any(l['product_id'][0] == product_id for l in lines)
    
    if has_product:
        refund_found = True
        refund_amount += cn['amount_total']

# 3. Check current stock level
quants = execute('stock.quant', 'search_read',
    [[['product_id', '=', product_id], ['location_id.usage', '=', 'internal']]],
    {'fields': ['quantity']})
current_stock = sum(q['quantity'] for q in quants)

result = {
    'return_found': return_found,
    'return_qty': return_qty,
    'refund_found': refund_found,
    'refund_amount': refund_amount,
    'current_stock': current_stock,
    'original_qty': setup['original_qty'],
    'expected_return_qty': 3,
    'unit_price': setup['unit_price'],
    'task_start_time': task_start_time
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="