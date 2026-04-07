#!/bin/bash
# Setup script for delivery_backorder_processing task
# Creates a Sales Order for 50 units where only 30 are in stock.
# The agent must validate the delivery for 30 and create a backorder for 20.

echo "=== Setting up delivery_backorder_processing ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Python script to set up data via XML-RPC
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

# 1. Create Customer
customer_name = "Northwind Safety Distributors"
existing_partner = execute('res.partner', 'search_read', [[['name', '=', customer_name]]], {'fields': ['id']})
if existing_partner:
    partner_id = existing_partner[0]['id']
    print(f"Using existing customer: {customer_name} (ID: {partner_id})")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': customer_name,
        'is_company': True,
        'email': 'logistics@northwind-safety.example.com',
        'street': '4500 Industrial Blvd',
        'city': 'Chicago',
        'zip': '60632'
    }])
    print(f"Created customer: {customer_name} (ID: {partner_id})")

# 2. Create Product (Storable)
product_name = "Industrial Safety Helmet - Class E"
existing_product = execute('product.template', 'search_read', [[['name', '=', product_name]]], {'fields': ['id']})
if existing_product:
    tmpl_id = existing_product[0]['id']
    print(f"Using existing product template: {product_name} (ID: {tmpl_id})")
    # Clean up existing stock/moves if reusing (complex, simpler to assume clean slate or just add to it)
else:
    tmpl_id = execute('product.template', 'create', [{
        'name': product_name,
        'type': 'product',  # Storable product
        'list_price': 45.00,
        'standard_price': 22.50,
        'sale_ok': True,
        'purchase_ok': True
    }])
    print(f"Created product: {product_name} (ID: {tmpl_id})")

# Get Product Variant ID
variants = execute('product.product', 'search_read', [[['product_tmpl_id', '=', tmpl_id]]], {'fields': ['id']})
product_id = variants[0]['id']

# 3. Set Inventory (30 units)
# Find stock location
stock_locs = execute('stock.location', 'search_read', [[['usage', '=', 'internal'], ['name', '=', 'Stock']]], {'fields': ['id']})
if not stock_locs:
    # Fallback to any internal location
    stock_locs = execute('stock.location', 'search_read', [[['usage', '=', 'internal']]], {'fields': ['id']})
location_id = stock_locs[0]['id']

# Update quantity using stock.quant
# Note: In Odoo 16+, direct write to quantity works if inventory_quantity_set is handled, 
# but easiest way via API is creating a quant or updating it.
# We will check current qty first.
quants = execute('stock.quant', 'search_read', 
    [[['product_id', '=', product_id], ['location_id', '=', location_id]]], 
    {'fields': ['id', 'quantity']})

current_qty = quants[0]['quantity'] if quants else 0.0
target_qty = 30.0

if current_qty != target_qty:
    # We can use stock.change.product.qty wizard or create an inventory adjustment.
    # Simpler: Create a stock.quant record (or write to it) if we have permissions.
    # In newer Odoo, we set 'inventory_quantity' and call 'action_apply_inventory'.
    
    if quants:
        quant_id = quants[0]['id']
        execute('stock.quant', 'write', [[quant_id], {'inventory_quantity': target_qty}])
    else:
        quant_id = execute('stock.quant', 'create', [{
            'product_id': product_id,
            'location_id': location_id,
            'inventory_quantity': target_qty
        }])
    
    execute('stock.quant', 'action_apply_inventory', [[quant_id]])
    print(f"Set stock level to {target_qty} units")

# 4. Create Sales Order (50 units)
so_id = execute('sale.order', 'create', [{
    'partner_id': partner_id,
    'payment_term_id': 1, # Immediate/30 days usually exists
}])

execute('sale.order.line', 'create', [{
    'order_id': so_id,
    'product_id': product_id,
    'product_uom_qty': 50.0,
    'price_unit': 45.00
}])

print(f"Created Sales Order (ID: {so_id}) for 50 units")

# 5. Confirm Sales Order to generate Delivery
execute('sale.order', 'action_confirm', [[so_id]])
print("Confirmed Sales Order")

# 6. Find the generated Picking (Delivery Order)
# Wait a moment for async generation if needed
time.sleep(1)
pickings = execute('stock.picking', 'search_read', 
    [[['origin', 'ilike', execute('sale.order', 'read', [so_id], {'fields': ['name']})[0]['name']]]], 
    {'fields': ['id', 'name', 'state']})

if not pickings:
    print("ERROR: Delivery order not generated!")
    sys.exit(1)

picking_id = pickings[0]['id']
picking_name = pickings[0]['name']
print(f"Generated Delivery Order: {picking_name} (ID: {picking_id})")

# 7. Save Setup Metadata
setup_data = {
    'partner_id': partner_id,
    'product_id': product_id,
    'so_id': so_id,
    'original_picking_id': picking_id,
    'original_picking_name': picking_name,
    'expected_done_qty': 30.0,
    'expected_backorder_qty': 20.0
}

with open('/tmp/delivery_backorder_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("Setup data saved to /tmp/delivery_backorder_setup.json")
PYEOF

# Ensure Firefox is open to the home page (Agent starts here)
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="