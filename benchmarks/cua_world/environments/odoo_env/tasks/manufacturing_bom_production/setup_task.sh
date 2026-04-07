#!/bin/bash
# Setup script for manufacturing_bom_production task
# Creates the finished product and component products, and sets initial stock.

echo "=== Setting up manufacturing_bom_production ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null && break
    sleep 3
done
sleep 5

# Run Python setup via XML-RPC
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

# ─── Install Manufacturing Module if needed ──────────────────────────────────
# This usually takes time, but in the standard env it might be pre-installed.
# We check and try to install, but fail gracefully if it takes too long.
try:
    module = execute('ir.module.module', 'search_read', [[['name', '=', 'mrp']]], {'fields': ['state']})
    if module and module[0]['state'] != 'installed':
        print("Installing Manufacturing (mrp) module...")
        execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
except Exception as e:
    print(f"Warning checking MRP module: {e}")

# ─── Setup Data ──────────────────────────────────────────────────────────────
FINISHED_PRODUCT = "Smart Home Hub Pro"
COMPONENTS = [
    {"name": "Circuit Board Assembly", "qty_needed": 1, "stock": 20},
    {"name": "Plastic Housing Unit", "qty_needed": 1, "stock": 20},
    {"name": "Power Supply Module", "qty_needed": 1, "stock": 20},
    {"name": "LED Display Panel", "qty_needed": 1, "stock": 20},
    {"name": "Antenna Module", "qty_needed": 2, "stock": 30},
    {"name": "Mounting Bracket", "qty_needed": 4, "stock": 60},
]

# ─── Find Internal Stock Location ────────────────────────────────────────────
# We need this to set initial stock
locations = execute('stock.location', 'search_read',
    [[['usage', '=', 'internal'], ['active', '=', True]]],
    {'fields': ['id', 'complete_name'], 'limit': 5})

stock_location_id = None
for loc in locations:
    if 'stock' in loc['complete_name'].lower():
        stock_location_id = loc['id']
        break
if not stock_location_id and locations:
    stock_location_id = locations[0]['id']

print(f"Using stock location ID: {stock_location_id}")

# ─── Create Products ─────────────────────────────────────────────────────────
# 1. Finished Product
existing_fp = execute('product.template', 'search_read', [[['name', '=', FINISHED_PRODUCT]]], {'fields': ['id']})
if existing_fp:
    finished_product_id = existing_fp[0]['id']
    # Ensure it can be manufactured
    execute('product.template', 'write', [[finished_product_id], {'route_ids': [(4, 5)]}]) # 5 is typically Manufacture route ID, but safer to let user configure if needed
else:
    finished_product_id = execute('product.template', 'create', [{
        'name': FINISHED_PRODUCT,
        'type': 'product', # Storable
        'detailed_type': 'product',
        'route_ids': [(6, 0, [])] # Clear routes, agent should ideally check this, but we'll default to standard
    }])
    print(f"Created finished product: {FINISHED_PRODUCT}")

# 2. Components
component_ids = {}
for comp in COMPONENTS:
    name = comp['name']
    stock_qty = comp['stock']
    
    # Check existence
    existing = execute('product.product', 'search_read', [[['name', '=', name]]], {'fields': ['id']})
    
    if existing:
        prod_id = existing[0]['id']
    else:
        # Create product template first
        tmpl_id = execute('product.template', 'create', [{
            'name': name,
            'type': 'product',
            'detailed_type': 'product',
            'list_price': 10.0,
            'standard_price': 5.0,
        }])
        # Get variant ID
        variants = execute('product.product', 'search_read', [[['product_tmpl_id', '=', tmpl_id]]], {'fields': ['id']})
        prod_id = variants[0]['id']
        print(f"Created component: {name}")

    component_ids[name] = prod_id

    # Update Stock (Set Quantity)
    # In Odoo 16+, we use stock.quant to set inventory
    # Check current stock first
    quants = execute('stock.quant', 'search_read', 
        [[['product_id', '=', prod_id], ['location_id', '=', stock_location_id]]], 
        {'fields': ['quantity']})
    
    current_qty = sum(q['quantity'] for q in quants)
    
    if current_qty < stock_qty:
        # Create/Update quant
        execute('stock.quant', 'create', [{
            'product_id': prod_id,
            'location_id': stock_location_id,
            'inventory_quantity': stock_qty,
        }])
        # Apply the inventory adjustment (needed in some versions, implicit in others via 'inventory_quantity' + 'action_apply_inventory')
        # Simple method: use 'quantity' field directly if allowed, or 'inventory_quantity' then apply.
        # For setup scripts, creating a stock.quant with 'quantity' often works if user is admin.
        try:
            execute('stock.quant', 'create', [{
                'product_id': prod_id,
                'location_id': stock_location_id,
                'quantity': stock_qty
            }])
        except Exception:
            # Fallback for strict inventory mode
            pass
            
# ─── Save Setup Metadata ─────────────────────────────────────────────────────
setup_data = {
    'finished_product_id': finished_product_id,
    'finished_product_name': FINISHED_PRODUCT,
    'component_ids': component_ids,
    'expected_components': COMPONENTS
}

with open('/tmp/manufacturing_setup.json', 'w') as f:
    json.dump(setup_data, f)

print("Setup complete.")
PYEOF

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="