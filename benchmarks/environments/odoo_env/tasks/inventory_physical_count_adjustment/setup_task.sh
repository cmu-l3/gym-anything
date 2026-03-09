#!/bin/bash
# Setup script for inventory_physical_count_adjustment task
# Creates 3 storable products and sets their stock quantities to specific values.
# The physical count (different quantities) is written to the Desktop.
# The agent must perform the Physical Inventory in Odoo to reconcile.

echo "=== Setting up inventory_physical_count_adjustment ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# Wait for Odoo XML-RPC to be available
echo "Waiting for Odoo..."
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
from datetime import date

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

# ─── Product definitions (real product categories with realistic quantities) ──
PRODUCTS = [
    {
        'name': 'Wireless Ergonomic Keyboard',
        'internal_ref': 'WEK-100',
        'type': 'product',      # storable product
        'categ_name': 'All / Saleable',
        'system_qty': 47,       # what system thinks is in stock
        'physical_qty': 35,     # what the physical count found (less - items were lost/damaged)
        'list_price': 89.99,
        'standard_price': 54.00,
    },
    {
        'name': 'USB-C Multiport Docking Station',
        'internal_ref': 'DOCK-USB-C',
        'type': 'product',
        'categ_name': 'All / Saleable',
        'system_qty': 31,
        'physical_qty': 38,     # more than system (received goods not logged)
        'list_price': 149.99,
        'standard_price': 89.00,
    },
    {
        'name': 'Adjustable Monitor Arm - Single',
        'internal_ref': 'MON-ARM-S1',
        'type': 'product',
        'categ_name': 'All / Saleable',
        'system_qty': 19,
        'physical_qty': 12,     # less than system (breakage / theft)
        'list_price': 64.99,
        'standard_price': 38.50,
    },
]

# ─── Find the main internal stock location ───────────────────────────────────
locations = execute('stock.location', 'search_read',
    [[['usage', '=', 'internal'], ['active', '=', True],
      ['complete_name', 'ilike', 'WH']]],
    {'fields': ['id', 'name', 'complete_name'], 'limit': 10})

# Prefer WH/Stock
stock_location = None
for loc in locations:
    if 'stock' in loc.get('complete_name', '').lower() or 'Stock' in loc.get('name', ''):
        stock_location = loc
        break
if not stock_location and locations:
    stock_location = locations[0]
if not stock_location:
    # Try any internal location
    locations2 = execute('stock.location', 'search_read',
        [[['usage', '=', 'internal'], ['active', '=', True]]],
        {'fields': ['id', 'name', 'complete_name'], 'limit': 5})
    if locations2:
        stock_location = locations2[0]

if not stock_location:
    print("ERROR: No internal stock location found!", file=sys.stderr)
    sys.exit(1)

location_id = stock_location['id']
print(f"Using location: {stock_location['complete_name']} (id={location_id})")

# ─── Create or find the three products ───────────────────────────────────────
setup_products = []

for prod_def in PRODUCTS:
    # Check if product already exists (idempotent)
    existing = execute('product.template', 'search_read',
        [[['name', '=', prod_def['name']], ['active', '=', True]]],
        {'fields': ['id', 'name'], 'limit': 1})

    if existing:
        tmpl_id = existing[0]['id']
        print(f"Product already exists: {prod_def['name']} (id={tmpl_id})")
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': prod_def['name'],
            'default_code': prod_def['internal_ref'],
            'type': prod_def['type'],
            'purchase_ok': True,
            'sale_ok': True,
            'list_price': prod_def['list_price'],
            'standard_price': prod_def['standard_price'],
        }])
        print(f"Created product: {prod_def['name']} (id={tmpl_id})")

    # Get the product.product variant
    variants = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', tmpl_id], ['active', '=', True]]],
        {'fields': ['id', 'name'], 'limit': 1})
    if not variants:
        print(f"ERROR: No variant for {prod_def['name']}", file=sys.stderr)
        continue
    product_id = variants[0]['id']

    # ─── Set system stock quantity via stock.quant ────────────────────────────
    existing_quants = execute('stock.quant', 'search_read',
        [[['product_id', '=', product_id], ['location_id', '=', location_id]]],
        {'fields': ['id', 'quantity'], 'limit': 1})

    if existing_quants:
        quant_id = existing_quants[0]['id']
        execute('stock.quant', 'write', [[quant_id], {'quantity': prod_def['system_qty']}])
        print(f"  Set quant for {prod_def['name']}: qty={prod_def['system_qty']}")
    else:
        quant_id = execute('stock.quant', 'create', [{
            'product_id': product_id,
            'location_id': location_id,
            'quantity': float(prod_def['system_qty']),
        }])
        print(f"  Created quant for {prod_def['name']}: qty={prod_def['system_qty']}")

    setup_products.append({
        'tmpl_id': tmpl_id,
        'product_id': product_id,
        'name': prod_def['name'],
        'internal_ref': prod_def['internal_ref'],
        'system_qty': prod_def['system_qty'],
        'physical_qty': prod_def['physical_qty'],
        'location_id': location_id,
        'location_name': stock_location['complete_name'],
    })

if len(setup_products) < 3:
    print("ERROR: Could not set up all 3 products!", file=sys.stderr)
    sys.exit(1)

# ─── Save setup metadata ──────────────────────────────────────────────────────
setup_data = {
    'products': setup_products,
    'location_id': location_id,
    'location_name': stock_location['complete_name'],
    'min_reorder_qty': 15,
    'max_reorder_qty': 60,
}
with open('/tmp/inventory_physical_count_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("\n=== Setup Summary ===")
print(f"Location: {stock_location['complete_name']}")
print(f"{'Product':<40} {'System Qty':>10} {'Physical':>10} {'Delta':>8}")
print("-" * 72)
for p in setup_products:
    delta = p['physical_qty'] - p['system_qty']
    sign = '+' if delta >= 0 else ''
    print(f"{p['name']:<40} {p['system_qty']:>10} {p['physical_qty']:>10} {sign}{delta:>7}")
print("\nAgent task: adjust system quantities to match physical counts, then set reorder rules")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# ─── Write physical count file to agent's Desktop ────────────────────────────
# Read the setup data to get product details
python3 << 'PYEOF2'
import json

with open('/tmp/inventory_physical_count_setup.json') as f:
    setup = json.load(f)

lines = [
    "PHYSICAL INVENTORY COUNT RESULTS",
    "=" * 50,
    f"Count Date: {__import__('datetime').date.today().strftime('%B %d, %Y')}",
    f"Warehouse Location: {setup['location_name']}",
    "Counted by: Warehouse Team",
    "",
    "INSTRUCTIONS:",
    "These are the actual physical counts from the warehouse floor.",
    "The system quantities differ and need to be adjusted in Odoo.",
    "After adjustment, please set up reorder rules for each product.",
    "",
    f"{'Product Name':<45} {'Counted Qty':>12}",
    "-" * 60,
]
for p in setup['products']:
    lines.append(f"{p['name']:<45} {p['physical_qty']:>12}")

lines += [
    "",
    "REORDER RULE SETTINGS (apply to all 3 products):",
    "  Minimum Quantity: 15 units",
    "  Maximum Quantity: 60 units",
    "",
    "Please update Odoo Physical Inventory accordingly.",
]

content = "\n".join(lines)
with open('/home/ga/Desktop/physical_count.txt', 'w') as f:
    f.write(content)
print(content)
PYEOF2

chmod 644 /home/ga/Desktop/physical_count.txt

# ─── Record task start timestamp ─────────────────────────────────────────────
date +%s > /tmp/task_start_timestamp

# ─── Ensure Firefox is open at Odoo ──────────────────────────────────────────
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/odoo/inventory' &" 2>/dev/null
    sleep 5
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Physical count file: /home/ga/Desktop/physical_count.txt"
echo "Setup data: /tmp/inventory_physical_count_setup.json"
