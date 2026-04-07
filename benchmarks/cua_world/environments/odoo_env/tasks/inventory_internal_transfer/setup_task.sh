#!/bin/bash
# Setup script for inventory_internal_transfer task
# 1. Creates a sub-location "Quality Inspection Zone"
# 2. Creates products with initial stock
# 3. Generates the transfer request file on Desktop

echo "=== Setting up inventory_internal_transfer ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Execute Python setup script via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

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

# 1. Find main warehouse and stock location
warehouses = execute('stock.warehouse', 'search_read', [], {'fields': ['id', 'code', 'lot_stock_id'], 'limit': 1})
if not warehouses:
    print("ERROR: No warehouse found", file=sys.stderr)
    sys.exit(1)

wh = warehouses[0]
stock_loc_id = wh['lot_stock_id'][0]
print(f"Main Stock Location: {wh['lot_stock_id'][1]} (id={stock_loc_id})")

# 2. Create "Quality Inspection Zone" sub-location
sub_loc_name = "Quality Inspection Zone"
existing_loc = execute('stock.location', 'search_read', 
    [[['name', '=', sub_loc_name], ['location_id', '=', stock_loc_id]]], 
    {'fields': ['id', 'complete_name']})

if existing_loc:
    dest_loc_id = existing_loc[0]['id']
    dest_loc_name = existing_loc[0]['complete_name']
    print(f"Using existing sub-location: {dest_loc_name}")
else:
    dest_loc_id = execute('stock.location', 'create', [{
        'name': sub_loc_name,
        'location_id': stock_loc_id,
        'usage': 'internal',
        'active': True
    }])
    # Read back to get complete name
    loc_data = execute('stock.location', 'read', [dest_loc_id], {'fields': ['complete_name']})
    dest_loc_name = loc_data[0]['complete_name']
    print(f"Created sub-location: {dest_loc_name}")

# 3. Create Products and Set Initial Inventory
products_data = [
    {"name": "Industrial Safety Helmet - Class E", "init_qty": 50, "cost": 28.0},
    {"name": "High-Visibility Reflective Vest - XL", "init_qty": 75, "cost": 19.0}
]

setup_info = {
    "products": [],
    "source_location_id": stock_loc_id,
    "dest_location_id": dest_loc_id,
    "dest_location_name": dest_loc_name
}

for p in products_data:
    # Check if exists
    existing_prod = execute('product.product', 'search_read', [[['name', '=', p["name"]]]], {'fields': ['id']})
    if existing_prod:
        prod_id = existing_prod[0]['id']
    else:
        prod_id = execute('product.product', 'create', [{
            'name': p["name"],
            'type': 'product', # Storable
            'standard_price': p["cost"],
            'categ_id': 1 # All
        }])
    
    # Set inventory using stock.quant
    # In Odoo 16/17+, usually we create a quant and apply inventory
    execute('stock.quant', 'create', [{
        'product_id': prod_id,
        'location_id': stock_loc_id,
        'inventory_quantity': p["init_qty"]
    }])
    
    # Apply the inventory adjustment
    # Find the quant we just created (or updated)
    quants = execute('stock.quant', 'search', [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]])
    execute('stock.quant', 'action_apply_inventory', [quants])
    
    setup_info["products"].append({
        "id": prod_id,
        "name": p["name"],
        "initial_qty": p["init_qty"]
    })
    print(f"Product '{p['name']}' set to {p['init_qty']} units")

# Save setup info for export script
with open('/tmp/transfer_setup.json', 'w') as f:
    json.dump(setup_info, f)

PYEOF

# 4. Create the Transfer Request File on Desktop
cat > /home/ga/Desktop/transfer_request.txt << 'EOF'
INTERNAL TRANSFER REQUEST
=========================
Date: TODAY
Reference: QC-BATCH-2025-001
Requested by: Quality Assurance Department

FROM: WH/Stock (Main Warehouse)
TO:   WH/Stock/Quality Inspection Zone

Items to Transfer:
--------------------------------------------------
1. Industrial Safety Helmet - Class E    Qty: 20
2. High-Visibility Reflective Vest - XL  Qty: 30
--------------------------------------------------

Reason: Pre-shipment quality inspection batch
Priority: Normal
Notes: Please validate transfer upon completion.
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/transfer_request.txt

# Ensure Firefox is open (common setup)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="