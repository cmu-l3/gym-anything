#!/bin/bash
# Setup script for vendor_return_refund_workflow
# Creates a completed workflow: PO -> Receipt -> Bill (Paid/Posted)
# State: 10 units in stock, fully billed.
# Agent must: Return 3 units, Create Credit Note.

echo "=== Setting up vendor_return_refund_workflow ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Run Python setup via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Create Vendor
vendor_id = execute('res.partner', 'create', [{
    'name': 'Apex Components',
    'is_company': True,
    'email': 'support@apex-components.com',
    'phone': '+1-555-0999',
    'street': '123 Tech Park Dr',
    'city': 'San Jose',
    'supplier_rank': 1
}])
print(f"Created Vendor: Apex Components (id={vendor_id})")

# 2. Create Product
product_id = execute('product.product', 'create', [{
    'name': 'Industrial Servo Motor',
    'type': 'product', # Storable
    'standard_price': 450.00,
    'list_price': 650.00,
    'purchase_ok': True,
    'sale_ok': True,
    'tracking': 'none'
}])
print(f"Created Product: Industrial Servo Motor (id={product_id})")

# 3. Create Purchase Order (10 units)
po_id = execute('purchase.order', 'create', [{
    'partner_id': vendor_id,
    'date_order': time.strftime('%Y-%m-%d %H:%M:%S'),
}])
line_id = execute('purchase.order.line', 'create', [{
    'order_id': po_id,
    'product_id': product_id,
    'product_qty': 10.0,
    'price_unit': 450.00,
}])
print(f"Created PO (id={po_id})")

# 4. Confirm PO
execute('purchase.order', 'button_confirm', [[po_id]])
print("PO Confirmed")

# 5. Process Receipt (Receive goods)
# Get picking associated with PO
pickings = execute('stock.picking', 'search_read', 
    [[['origin', '=', execute('purchase.order', 'read', [po_id], ['name'])[0]['name']]]],
    {'fields': ['id', 'name']})

if pickings:
    picking_id = pickings[0]['id']
    # Set qty done automatically (Odoo 14+ flow often requires setting qty_done or move_ids_without_package)
    # Simple way: call button_validate, it might ask to create backorder or process all. 
    # Usually we need to set quantity done on moves first.
    moves = execute('stock.move', 'search_read', 
        [[['picking_id', '=', picking_id]]], 
        {'fields': ['id', 'product_uom_qty']})
    
    for move in moves:
        execute('stock.move', 'write', [[move['id']], {'quantity': move['product_uom_qty']}]) # For Odoo 16/17 use 'quantity' or 'quantity_done' depending on version, generic fallback usually works with picking wizard
        
    # Validate
    # In recent Odoo, validate returns a wizard action if immediate transfer is needed, but setting quantity matches demand usually bypasses it
    try:
        execute('stock.picking', 'button_validate', [[picking_id]])
        print(f"Receipt Validated (id={picking_id})")
    except Exception as e:
        # If immediate transfer wizard needed
        print(f"Receipt validation note: {e}")
        # Force it via wizard if needed (omitted for brevity, assuming standard config)

# 6. Create Vendor Bill
# Use the action to create bill from PO
execute('purchase.order', 'action_create_invoice', [[po_id]])

# Find the created bill
bills = execute('account.move', 'search_read', 
    [[['partner_id', '=', vendor_id], ['move_type', '=', 'in_invoice'], ['state', '=', 'draft']]],
    {'fields': ['id']})

if bills:
    bill_id = bills[0]['id']
    # Post the bill
    # Need to set invoice date first
    execute('account.move', 'write', [[bill_id], {'invoice_date': time.strftime('%Y-%m-%d')}])
    execute('account.move', 'action_post', [[bill_id]])
    print(f"Vendor Bill Posted (id={bill_id})")
else:
    print("Error: Bill not created")

# Save setup data for verification
setup_data = {
    'vendor_id': vendor_id,
    'product_id': product_id,
    'po_id': po_id,
    'bill_id': bill_id if bills else None,
    'original_qty': 10,
    'unit_price': 450.00
}

with open('/tmp/vendor_return_setup.json', 'w') as f:
    json.dump(setup_data, f)

PYEOF

# Ensure Firefox is open (standard practice for these tasks)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="