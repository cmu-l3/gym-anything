#!/bin/bash
# Setup script for landed_cost_import_allocation task

echo "=== Setting up Landed Cost Import Allocation ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the desktop file immediately so it's ready even if Odoo setup takes a moment
cat > /home/ga/Desktop/import_shipment_costs.txt << 'EOF'
==============================================
  IMPORT SHIPMENT — COST ALLOCATION MEMO
==============================================

Supplier: Shenzhen Global Components Ltd

Products Received:
  - Industrial Relay Module: 40 units
  - Programmable Logic Controller: 20 units
  - Servo Motor Drive Unit: 10 units
  Total Product Value: $6,400.00

Additional Costs to Allocate:
  1. Ocean Freight:    $2,400.00
  2. Customs Duty:     $1,800.00
  3. Cargo Insurance:    $600.00
  Total Additional:   $4,800.00

Allocation Method: By Current Cost
(Costs distributed proportionally to each product's value)

Action Required:
  Create a Landed Cost record in Odoo Inventory,
  link it to the receipt for this shipment, enter
  the three cost lines above, and validate.
==============================================
EOF
chmod 644 /home/ga/Desktop/import_shipment_costs.txt
chown ga:ga /home/ga/Desktop/import_shipment_costs.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null && break
    sleep 3
done
sleep 2

# Python script to setup Odoo data
python3 << 'PYEOF'
import xmlrpc.client
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

# 1. Install/Activate stock_landed_costs module
print("Checking stock_landed_costs module...")
module = execute('ir.module.module', 'search_read',
    [[['name', '=', 'stock_landed_costs']]],
    {'fields': ['state', 'id'], 'limit': 1})

if module and module[0]['state'] != 'installed':
    print("Installing stock_landed_costs...")
    execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
    # Wait for install to propagate/reload registry if needed (usually immediate in script flow)
    time.sleep(5) 
    
    # Enable Landed Costs in Settings if needed (often auto-enabled by module install, but good to check)
    # In Odoo 16/17, just installing the module usually enables the menu.

# 2. Configure Product Category for Automated Valuation
# We need a category where Landed Costs can be applied (Automated + FIFO/AVCO)
print("Configuring Product Category...")
# Check for expenses account type
account_types = execute('account.account.type', 'search_read', [[['name', '=', 'Expenses']]], {'limit': 1})
# Find or create accounts if missing (using demo data accounts usually works)
# We'll use a generic "Expenses" account for stock input/output difference if specific ones aren't found
# For simplicity in this task, we rely on existing demo accounts or create basic ones if totally missing.
# However, usually demo data has "All / Saleable". We will modify it or create a sub-category.

category_id = execute('product.category', 'create', [{
    'name': 'Imported Electronics',
    'parent_id': 1, # All
    'property_valuation': 'real_time', # Automated
    'property_cost_method': 'fifo',    # FIFO
    # We rely on default accounts inherited or standard demo accounts. 
    # If this fails in a clean env, we'd need to fetch account IDs.
    # Assuming standard Odoo demo data has required accounts set on parent 'All'.
}])
print(f"Created Category: Imported Electronics (id={category_id})")

# 3. Create Vendor
vendor_id = execute('res.partner', 'create', [{
    'name': 'Shenzhen Global Components Ltd',
    'is_company': True,
    'supplier_rank': 1,
}])
print(f"Created Vendor: Shenzhen Global Components Ltd (id={vendor_id})")

# 4. Create Products
products_data = [
    {'name': 'Industrial Relay Module', 'standard_price': 50.0, 'list_price': 85.0},
    {'name': 'Programmable Logic Controller', 'standard_price': 120.0, 'list_price': 250.0},
    {'name': 'Servo Motor Drive Unit', 'standard_price': 200.0, 'list_price': 380.0},
]

product_ids = []
for p in products_data:
    pid = execute('product.product', 'create', [{
        'name': p['name'],
        'type': 'product', # Storable
        'categ_id': category_id,
        'standard_price': p['standard_price'],
        'list_price': p['list_price'],
        'purchase_ok': True,
    }])
    product_ids.append(pid)
    print(f"Created Product: {p['name']} (id={pid})")

# 5. Create Purchase Order
po_id = execute('purchase.order', 'create', [{
    'partner_id': vendor_id,
    'order_line': [
        (0, 0, {'product_id': product_ids[0], 'product_qty': 40, 'price_unit': 50.0}),  # 2000
        (0, 0, {'product_id': product_ids[1], 'product_qty': 20, 'price_unit': 120.0}), # 2400
        (0, 0, {'product_id': product_ids[2], 'product_qty': 10, 'price_unit': 200.0}), # 2000
    ]
}])
print(f"Created PO: {po_id}")

# 6. Confirm PO
execute('purchase.order', 'button_confirm', [[po_id]])

# 7. Receive Products (Validate Picking)
# Get picking
picking_ids = execute('purchase.order', 'read', [po_id], ['picking_ids'])[0]['picking_ids']
picking_id = picking_ids[0]

# Set quantities done
picking = execute('stock.picking', 'read', [picking_id], ['move_ids_without_package'])[0]
moves = execute('stock.move', 'read', picking['move_ids_without_package'], ['id', 'product_uom_qty'])

for move in moves:
    execute('stock.move', 'write', [[move['id']], {'quantity': move['product_uom_qty']}]) # Odoo 17 uses 'quantity' for done qty in some contexts, or 'quantity_done'

# Button validate
execute('stock.picking', 'button_validate', [[picking_id]])
print(f"Validated Picking: {picking_id}")

# 8. Create Landed Cost Product Types (Service products) if they don't exist
# Odoo landed costs need a service product with 'landed_cost_ok' = True (in older versions) or just use standard expenses
# In Odoo 16/17, we usually add lines directly, but they reference a product.
# We create "Service" products for the costs.
cost_products = ['Ocean Freight', 'Customs Duty', 'Cargo Insurance']
for cp_name in cost_products:
    execute('product.product', 'create', [{
        'name': cp_name,
        'type': 'service',
        # 'landed_cost_ok': True, # Field might be required depending on version, safely omitted if recent Odoo allows any service
    }])

# Save setup info
import json
setup_info = {
    'vendor_id': vendor_id,
    'po_id': po_id,
    'picking_id': picking_id,
    'product_ids': product_ids
}
with open('/tmp/landed_cost_setup.json', 'w') as f:
    json.dump(setup_info, f)

print("Setup Complete.")
PYEOF

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true