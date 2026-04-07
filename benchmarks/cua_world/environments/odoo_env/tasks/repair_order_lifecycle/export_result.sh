#!/bin/bash
# Export script for repair_order_lifecycle task

echo "=== Exporting repair_order_lifecycle Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    # If Odoo is down, return empty failure
    with open('/tmp/repair_order_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
    sys.exit(0)

def execute(model, method, *args, **kwargs):
    return models.execute_kw(DB, uid, PASSWORD, model, method, list(args), kwargs)

# Fetch Customer
partners = execute('res.partner', 'search_read', [['name', '=', 'Constructors Inc']], {'limit': 1})
if not partners:
    result = {'error': 'Customer not found'}
else:
    partner_id = partners[0]['id']
    
    # Search for Repair Orders for this customer
    # Odoo Repair model is 'repair.order'
    repair_orders = execute('repair.order', 'search_read', 
        [['partner_id', '=', partner_id]], 
        {'fields': ['id', 'name', 'state', 'product_id', 'move_ids', 'invoice_id'], 'order': 'id desc', 'limit': 1})
    
    if not repair_orders:
        result = {
            'repair_found': False,
            'customer_found': True
        }
    else:
        ro = repair_orders[0]
        ro_id = ro['id']
        
        # Check lines (operations)
        # In newer Odoo versions, parts are in 'move_ids' or 'operations'
        # We need to inspect what lines are attached.
        # Often 'repair.line' (Odoo <17) or 'stock.move'/'repair.line' (Odoo 17+)
        
        # Try getting repair lines (parts) and fees lines (labor - older Odoo) or just lines
        parts_found = False
        labor_found = False
        labor_qty = 0.0
        
        # Attempt to read 'operations' if it exists, otherwise check linked models
        # We will try a broad search for lines linked to this repair_id
        
        # Check for High-Capacity Battery
        # Note: Model names change between versions. 'repair.line' is standard for operations.
        lines = execute('repair.line', 'search_read', [['repair_id', '=', ro_id]], ['name', 'product_id', 'product_uom_qty', 'type', 'price_subtotal'])
        
        for line in lines:
            p_name = line['product_id'][1] if isinstance(line['product_id'], list) else ''
            qty = line['product_uom_qty']
            
            if 'Battery' in p_name:
                parts_found = True
            if 'Labor' in p_name:
                labor_found = True
                labor_qty = qty

        # Check Invoice
        invoice_id = ro.get('invoice_id')
        invoice_state = 'none'
        invoice_amount = 0.0
        
        if invoice_id:
            # invoice_id is [id, name]
            inv_id = invoice_id[0]
            inv_data = execute('account.move', 'read', [inv_id], ['state', 'amount_total'])
            if inv_data:
                invoice_state = inv_data[0]['state']
                invoice_amount = inv_data[0]['amount_total']
        
        result = {
            'repair_found': True,
            'repair_state': ro['state'],
            'parts_found': parts_found,
            'labor_found': labor_found,
            'labor_qty': labor_qty,
            'invoice_created': bool(invoice_id),
            'invoice_state': invoice_state,
            'invoice_amount': invoice_amount
        }

with open('/tmp/repair_order_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported."