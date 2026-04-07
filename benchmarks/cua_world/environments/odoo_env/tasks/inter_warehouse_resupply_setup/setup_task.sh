#!/bin/bash
# Setup script for inter_warehouse_resupply_setup
# Prepares the "San Francisco" warehouse with stock and ensures the product exists.

echo "=== Setting up Inter-Warehouse Resupply Task ==="

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

# Run Python setup via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys

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

# 1. Ensure Inventory app is installed (usually is in demo)
# (Skipped, assumed installed in odoo_env base)

# 2. Enable Multi-Warehouse and Multi-Step Routes groups for the user
# This allows the agent to see the menus immediately without needing a browser refresh/relog
# strictly speaking, but the agent still needs to verify settings.
# We enable the "features" in res.config.settings logic by adding the user to groups.
print("Enabling Inventory features (Multi-Warehouse, Multi-Step Routes)...")
# Find groups
groups = execute('res.groups', 'search_read', 
    [[['name', 'in', ['Multi-Warehouses', 'Multi-Step Routes', 'Manage Push and Pull inventory flows']]]], 
    {'fields': ['id', 'name']})

group_ids = [g['id'] for g in groups]
if group_ids:
    # Add admin user (uid) to these groups
    execute('res.users', 'write', [[uid], {'groups_id': [(4, gid) for gid in group_ids]}])

# 3. Find/Create Product 'Acoustic Bloc Screen'
print("Configuring product 'Acoustic Bloc Screen'...")
products = execute('product.product', 'search_read', 
    [[['name', '=', 'Acoustic Bloc Screen']]], 
    {'fields': ['id', 'name', 'type']})

if products:
    product = products[0]
    # Ensure it is storable
    if product['type'] != 'product':
        execute('product.product', 'write', [[product['id']], {'type': 'product'}])
    product_id = product['id']
    print(f"Using existing product: {product['name']} (id={product_id})")
else:
    # Create it
    product_id = execute('product.product', 'create', [{
        'name': 'Acoustic Bloc Screen',
        'type': 'product', # Storable
        'list_price': 295.0,
        'standard_price': 150.0,
    }])
    print(f"Created product: Acoustic Bloc Screen (id={product_id})")

# 4. Ensure Stock in San Francisco
# Find SF Warehouse (usually code 'WH' or 'SF' in demo data)
warehouses = execute('stock.warehouse', 'search_read', [], {'fields': ['id', 'code', 'lot_stock_id']})
sf_wh = next((w for w in warehouses if w['code'] in ['WH', 'SF']), warehouses[0])
sf_location_id = sf_wh['lot_stock_id'][0]
print(f"Using Source Warehouse: {sf_wh['code']} (Location ID: {sf_location_id})")

# Update quantity to 100
# We use 'stock.quant' create/write
# Check existing quant
quants = execute('stock.quant', 'search_read', 
    [[['product_id', '=', product_id], ['location_id', '=', sf_location_id]]], 
    {'fields': ['id', 'quantity']})

if quants:
    execute('stock.quant', 'write', [[quants[0]['id']], {'inventory_quantity': 100}])
    execute('stock.quant', 'action_apply_inventory', [[quants[0]['id']]])
else:
    execute('stock.quant', 'create', [{
        'product_id': product_id,
        'location_id': sf_location_id,
        'inventory_quantity': 100,
    }])
    # Find it again to apply (create doesn't apply automatically in some versions)
    quants = execute('stock.quant', 'search_read', 
        [[['product_id', '=', product_id], ['location_id', '=', sf_location_id]]], 
        {'fields': ['id']})
    if quants:
        execute('stock.quant', 'action_apply_inventory', [[quants[0]['id']]])

print("Stock updated in Source Warehouse.")

PYEOF

# Ensure Firefox is open and maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="