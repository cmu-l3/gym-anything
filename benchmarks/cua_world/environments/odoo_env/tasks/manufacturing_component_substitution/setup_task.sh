#!/bin/bash
# Setup script for manufacturing_component_substitution task
# Creates products, BOM, and stock levels to simulate a shortage scenario.

echo "=== Setting up manufacturing_component_substitution ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Record task start time
date +%s > /tmp/task_start_timestamp

# Execute Python setup script
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

# 1. Install MRP module if needed
try:
    mrp_module = execute('ir.module.module', 'search_read', [[['name', '=', 'mrp']]], {'fields': ['state']})
    if mrp_module and mrp_module[0]['state'] != 'installed':
        print("Installing Manufacturing module...")
        execute('ir.module.module', 'button_immediate_install', [[mrp_module[0]['id']]])
except Exception as e:
    print(f"Warning checking MRP module: {e}")

# 2. Create Products
products_data = [
    {
        'name': 'Centrifugal Pump CP-200',
        'type': 'product', # Storable
        'route_ids': [], # Will be set to Manufacture later if needed, but default is usually fine
    },
    {
        'name': 'Pump Housing',
        'type': 'product',
        'standard_price': 40.0,
    },
    {
        'name': 'Standard Gasket G-100',
        'type': 'product',
        'standard_price': 2.0,
    },
    {
        'name': 'Premium Gasket G-200',
        'type': 'product',
        'standard_price': 8.0,
    }
]

created_products = {}

for p_data in products_data:
    # Check if exists
    existing = execute('product.template', 'search_read', [[['name', '=', p_data['name']]]], {'fields': ['id']})
    if existing:
        tmpl_id = existing[0]['id']
    else:
        tmpl_id = execute('product.template', 'create', [p_data])
    
    # Get product.product ID
    variant = execute('product.product', 'search_read', [[['product_tmpl_id', '=', tmpl_id]]], {'fields': ['id']})
    created_products[p_data['name']] = variant[0]['id']
    print(f"Product '{p_data['name']}' ready (ID: {variant[0]['id']})")

# 3. Update Stock Quantities
# We need a location. Usually 'WH/Stock'
locs = execute('stock.location', 'search_read', [[['usage', '=', 'internal']]], {'limit': 1})
if not locs:
    print("Error: No internal location found")
    sys.exit(1)
location_id = locs[0]['id']

# Set Quantities:
# Housing: 100
# Standard Gasket: 0 (Critical!)
# Premium Gasket: 100

stock_updates = [
    (created_products['Pump Housing'], 100),
    (created_products['Standard Gasket G-100'], 0), # Explicitly ensure 0
    (created_products['Premium Gasket G-200'], 100)
]

for pid, qty in stock_updates:
    # Check current qty
    quants = execute('stock.quant', 'search_read', [[['product_id', '=', pid], ['location_id', '=', location_id]]])
    current = sum(q['quantity'] for q in quants)
    
    if current != qty:
        # Create inventory adjustment (simple update via stock.quant)
        # Note: In newer Odoo versions, writing to quantity directly works if user has rights
        try:
             execute('stock.quant', 'create', [{
                'product_id': pid,
                'location_id': location_id,
                'inventory_quantity': qty,
            }])
             # Apply logic varies by version, simplified here assumes direct create or simple write works for demo
        except Exception:
             # Fallback or if quant exists, write to it
             if quants:
                 execute('stock.quant', 'write', [[quants[0]['id']], {'inventory_quantity': qty}])

# 4. Create Bill of Materials
# Pump = 1 Housing + 1 Standard Gasket
bom_data = {
    'product_tmpl_id': execute('product.product', 'read', [created_products['Centrifugal Pump CP-200']], ['product_tmpl_id'])[0]['product_tmpl_id'][0],
    'product_qty': 1.0,
    'bom_line_ids': [
        (0, 0, {'product_id': created_products['Pump Housing'], 'product_qty': 1.0}),
        (0, 0, {'product_id': created_products['Standard Gasket G-100'], 'product_qty': 1.0})
    ]
}

# Check if BOM exists
existing_bom = execute('mrp.bom', 'search_read', [[['product_tmpl_id', '=', bom_data['product_tmpl_id']]]], {'fields': ['id']})
if existing_bom:
    bom_id = existing_bom[0]['id']
    print(f"Using existing BOM: {bom_id}")
    # We should verify lines here but assuming clean state for simplicity or manual fix
else:
    bom_id = execute('mrp.bom', 'create', [bom_data])
    print(f"Created BOM: {bom_id}")

# Save setup data
setup_info = {
    'products': created_products,
    'bom_id': bom_id,
    'initial_stock': {
        'housing': 100,
        'standard_gasket': 0,
        'premium_gasket': 100
    }
}

with open('/tmp/mrp_sub_setup.json', 'w') as f:
    json.dump(setup_info, f)

print("Setup Complete.")
PYEOF

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="