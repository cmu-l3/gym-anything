#!/bin/bash
# Setup script for sales_phantom_kit_assembly task
# 1. Installs MRP module (required for BoM).
# 2. Creates the 3 component products with sufficient stock.
# 3. Ensures customer 'Azure Interior' exists.

echo "=== Setting up sales_phantom_kit_assembly ==="

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
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Install MRP module if not installed (needed for BoM)
module_state = execute('ir.module.module', 'search_read',
    [[['name', '=', 'mrp']]], {'fields': ['state']})
if not module_state or module_state[0]['state'] != 'installed':
    print("Installing Manufacturing (mrp) module...")
    # This might take a while, but it's necessary for BoM functionality
    execute('ir.module.module', 'button_immediate_install', [[module_state[0]['id']]])

# 2. Ensure Customer Exists
customer_name = "Azure Interior"
existing_cust = execute('res.partner', 'search_read', [[['name', '=', customer_name]]], {'fields': ['id']})
if not existing_cust:
    customer_id = execute('res.partner', 'create', [{'name': customer_name, 'is_company': True}])
    print(f"Created customer: {customer_name}")
else:
    customer_id = existing_cust[0]['id']
    print(f"Using customer: {customer_name}")

# 3. Create Component Products and Add Stock
components = [
    {'name': 'USB Microphone', 'price': 120.0},
    {'name': '10-inch Ring Light', 'price': 45.0},
    {'name': 'Pop-up Green Screen', 'price': 80.0}
]

setup_data = {'components': [], 'customer_id': customer_id}

# Find main stock location (usually WH/Stock)
locs = execute('stock.location', 'search_read', [[['usage', '=', 'internal']]], {'limit': 1})
location_id = locs[0]['id'] if locs else 1

for comp in components:
    # Check if exists
    existing = execute('product.product', 'search_read', [[['name', '=', comp['name']]]], {'fields': ['id']})
    if existing:
        prod_id = existing[0]['id']
    else:
        prod_id = execute('product.product', 'create', [{
            'name': comp['name'],
            'type': 'product', # Storable
            'list_price': comp['price'],
            'standard_price': comp['price'] * 0.6
        }])
    
    # Update stock (Inventory Adjustment) so they are available for delivery
    # Using 'stock.quant' to set quantity directly
    execute('stock.quant', 'create', [{
        'product_id': prod_id,
        'location_id': location_id,
        'inventory_quantity': 50, # Plenty of stock
    }])
    # Apply the inventory
    # Note: In newer Odoo versions, writing inventory_quantity and calling action_apply_inventory is preferred
    # but direct creation often works for demo setup. To be safe, let's try to apply.
    try:
        quant_ids = execute('stock.quant', 'search', [[['product_id', '=', prod_id], ['location_id', '=', location_id]]])
        execute('stock.quant', 'action_apply_inventory', [quant_ids])
    except Exception as e:
        print(f"Warning setting stock for {comp['name']}: {e}")

    print(f"Prepared component: {comp['name']} (ID: {prod_id})")
    setup_data['components'].append({'id': prod_id, 'name': comp['name']})

# Write setup data
with open('/tmp/phantom_kit_setup.json', 'w') as f:
    json.dump(setup_data, f)

print("Setup complete.")
PYEOF

# Ensure Firefox is open and maximized
DISPLAY=:1 wmctrl -r "Odoo" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="