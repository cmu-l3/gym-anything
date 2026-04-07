#!/bin/bash
# Setup script for smartdesk_product_launch_validation task
# Installs required modules, enables features, creates component products
# with stock and vendor pricing, creates vendors and customer.
# The agent must create: product template with variants, BOMs, pricelist, test MO, test SO.

echo "=== Setting up smartdesk_product_launch_validation ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/smartdesk_setup.json /tmp/smartdesk_result.json /tmp/task_result.json 2>/dev/null || true

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 5

# Run Python setup via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin'
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

# ─── Install Required Modules ────────────────────────────────────────────────
MODULES_TO_INSTALL = ['sale_management', 'mrp', 'purchase']

for mod_name in MODULES_TO_INSTALL:
    try:
        module = execute('ir.module.module', 'search_read',
            [[['name', '=', mod_name]]], {'fields': ['state']})
        if module and module[0]['state'] != 'installed':
            print(f"Installing {mod_name} module...")
            execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
            time.sleep(3)
            print(f"  {mod_name} installed.")
        else:
            print(f"  {mod_name} already installed.")
    except Exception as e:
        print(f"Warning installing {mod_name}: {e}")

# ─── Enable Product Variants Feature ─────────────────────────────────────────
print("Enabling product variants and pricelists...")
try:
    settings_id = execute('res.config.settings', 'create', [{
        'group_product_variant': True,
        'group_sale_pricelist': True,
        'group_product_pricelist': True,
    }])
    execute('res.config.settings', 'execute', [[settings_id]])
    print("  Features enabled.")
except Exception as e:
    print(f"  Warning enabling features: {e}")

# ─── Find Internal Stock Location ────────────────────────────────────────────
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

# ─── Create Vendors ──────────────────────────────────────────────────────────
def get_or_create_partner(name, is_supplier=False, is_customer=False, extra_vals=None):
    existing = execute('res.partner', 'search_read',
        [[['name', '=', name], ['is_company', '=', True]]],
        {'fields': ['id'], 'limit': 1})
    if existing:
        pid = existing[0]['id']
        print(f"Using existing partner: {name} (id={pid})")
        return pid
    vals = {
        'name': name,
        'is_company': True,
    }
    if is_supplier:
        vals['supplier_rank'] = 1
    if is_customer:
        vals['customer_rank'] = 1
    if extra_vals:
        vals.update(extra_vals)
    pid = execute('res.partner', 'create', [vals])
    print(f"Created partner: {name} (id={pid})")
    return pid

techmotion_id = get_or_create_partner("TechMotion Supply", is_supplier=True, extra_vals={
    'street': '1200 Circuit Way',
    'city': 'Shenzhen',
    'country_id': 48,  # China
    'email': 'sales@techmotion-supply.com',
    'phone': '+86 755 8888 1234',
})

nordic_id = get_or_create_partner("Nordic Timber Co.", is_supplier=True, extra_vals={
    'street': 'Industrivägen 42',
    'city': 'Gothenburg',
    'country_id': 196,  # Sweden
    'email': 'orders@nordictimber.se',
    'phone': '+46 31 555 0088',
})

# ─── Create Customer ─────────────────────────────────────────────────────────
cascade_id = get_or_create_partner("Cascade Furniture Partners", is_customer=True, extra_vals={
    'street': '890 Commerce Blvd',
    'city': 'Portland',
    'zip': '97201',
    'country_id': 233,  # United States
    'email': 'procurement@cascadefurniture.com',
    'phone': '(503) 555-0199',
})

# ─── Define Component Products ───────────────────────────────────────────────
COMPONENTS = [
    {"name": "Linear Actuator",  "ref": "LIN-ACT",   "cost": 85.00,  "stock": 100, "vendor_id": techmotion_id, "vendor_price": 85.00},
    {"name": "Control Unit",     "ref": "CTRL-UNIT",  "cost": 120.00, "stock": 100, "vendor_id": techmotion_id, "vendor_price": 120.00},
    {"name": "Cable Harness",    "ref": "CBL-HRNS",   "cost": 15.00,  "stock": 100, "vendor_id": techmotion_id, "vendor_price": 15.00},
    {"name": "Steel Frame",      "ref": "STL-FRM",    "cost": 95.00,  "stock": 100, "vendor_id": nordic_id,     "vendor_price": 95.00},
    {"name": "Oak Board",        "ref": "OAK-BRD",    "cost": 180.00, "stock": 100, "vendor_id": nordic_id,     "vendor_price": 180.00},
    {"name": "White Laminate",   "ref": "WHT-LAM",    "cost": 110.00, "stock": 100, "vendor_id": nordic_id,     "vendor_price": 110.00},
    {"name": "Walnut Board",     "ref": "WNT-BRD",    "cost": 220.00, "stock": 100, "vendor_id": nordic_id,     "vendor_price": 220.00},
    {"name": "Hardware Kit",     "ref": "HW-KIT",     "cost": 25.00,  "stock": 100, "vendor_id": nordic_id,     "vendor_price": 25.00},
]

component_product_ids = {}   # name -> product.product id
component_tmpl_ids = {}      # name -> product.template id

for comp in COMPONENTS:
    name = comp['name']

    # Check if exists
    existing = execute('product.template', 'search_read',
        [[['name', '=', name], ['active', '=', True]]],
        {'fields': ['id'], 'limit': 1})

    if existing:
        tmpl_id = existing[0]['id']
        # Update cost to ensure it's correct
        execute('product.template', 'write', [[tmpl_id], {
            'standard_price': comp['cost'],
            'default_code': comp['ref'],
        }])
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': name,
            'default_code': comp['ref'],
            'type': 'product',
            'detailed_type': 'product',
            'sale_ok': True,
            'purchase_ok': True,
            'list_price': comp['cost'] * 1.5,
            'standard_price': comp['cost'],
        }])
        print(f"Created component: {name} (tmpl_id={tmpl_id})")

    component_tmpl_ids[name] = tmpl_id

    # Get product.product variant ID
    variants = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', tmpl_id], ['active', '=', True]]],
        {'fields': ['id'], 'limit': 1})
    prod_id = variants[0]['id'] if variants else None
    component_product_ids[name] = prod_id

    # Set initial stock
    if comp['stock'] > 0 and stock_location_id and prod_id:
        # Check if quant already exists
        quants = execute('stock.quant', 'search_read',
            [[['product_id', '=', prod_id], ['location_id', '=', stock_location_id]]],
            {'fields': ['id', 'quantity']})
        if quants:
            # Update existing quant
            execute('stock.quant', 'write', [[quants[0]['id']], {
                'inventory_quantity': comp['stock'],
            }])
            try:
                execute('stock.quant', 'action_apply_inventory', [[quants[0]['id']]])
            except Exception:
                pass
        else:
            quant_id = execute('stock.quant', 'create', [{
                'product_id': prod_id,
                'location_id': stock_location_id,
                'inventory_quantity': comp['stock'],
            }])
            try:
                execute('stock.quant', 'action_apply_inventory', [[quant_id]])
            except Exception:
                pass
        print(f"  Set stock for {name}: {comp['stock']} units")

    # Create vendor pricelist (product.supplierinfo)
    if comp.get('vendor_id') and tmpl_id:
        existing_supinfo = execute('product.supplierinfo', 'search_read',
            [[['partner_id', '=', comp['vendor_id']], ['product_tmpl_id', '=', tmpl_id]]],
            {'fields': ['id'], 'limit': 1})
        if not existing_supinfo:
            execute('product.supplierinfo', 'create', [{
                'partner_id': comp['vendor_id'],
                'product_tmpl_id': tmpl_id,
                'price': comp['vendor_price'],
                'min_qty': 1,
            }])
            print(f"  Vendor pricing: {name} @ ${comp['vendor_price']}")

print(f"\nAll {len(COMPONENTS)} components created with stock and vendor pricing.")

# ─── Write Desktop Reference File ────────────────────────────────────────────
guide_text = """SmartDesk Pro — Product Launch Configuration Guide
====================================================

PRODUCT: SmartDesk Pro (motorized standing desk)
  Base Price: $1,200 (Standard size)
  Size attribute:  Standard / Large (+$300)
  Finish attribute: Oak / White / Walnut (+$200)
  => 6 variants total

BILL OF MATERIALS (per desk):
  Motorized Lift Frame x1       (sub-assembly, all variants)
  Desktop Surface x1            (variant-specific — see below)
  Hardware Kit x1               (all variants)

  Surface mapping:
    Oak finish    => Oak Board
    White finish  => White Laminate
    Walnut finish => Walnut Board

MOTORIZED LIFT FRAME sub-assembly BOM:
  Linear Actuator x2
  Steel Frame x1
  Control Unit x1
  Cable Harness x1

COMPONENT VENDORS (already configured in Odoo):
  TechMotion Supply:  Linear Actuator, Control Unit, Cable Harness
  Nordic Timber Co.:  Steel Frame, Oak Board, White Laminate,
                      Walnut Board, Hardware Kit

WHOLESALE PRICELIST: "Authorized Dealer Network"
  1-4 units:  List price
  5-9 units:  15% discount
  10+ units:  25% discount

VALIDATION STEPS:
  1. Manufacture 1x Standard/Walnut — verify correct components consumed
  2. Sales order for Cascade Furniture Partners:
     8x SmartDesk Pro (Standard / Walnut) at dealer pricing
     Unit = ($1,200 + $200) x 0.85 = $1,190.00
     Total = $9,520.00
"""

with open('/home/ga/Desktop/smartdesk_launch_guide.txt', 'w') as f:
    f.write(guide_text)

import os
os.chmod('/home/ga/Desktop/smartdesk_launch_guide.txt', 0o666)

# Also ensure the file is owned by ga
import subprocess
subprocess.run(['chown', 'ga:ga', '/home/ga/Desktop/smartdesk_launch_guide.txt'],
               capture_output=True)

print("Desktop reference file written.")

# ─── Save Setup Metadata ─────────────────────────────────────────────────────
setup_data = {
    'vendor_ids': {
        'techmotion': techmotion_id,
        'nordic': nordic_id,
    },
    'customer_id': cascade_id,
    'customer_name': 'Cascade Furniture Partners',
    'component_product_ids': component_product_ids,
    'component_tmpl_ids': component_tmpl_ids,
    'stock_location_id': stock_location_id,
}

with open('/tmp/smartdesk_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("\n=== Setup Summary ===")
print(f"Vendors: TechMotion Supply (id={techmotion_id}), Nordic Timber Co. (id={nordic_id})")
print(f"Customer: Cascade Furniture Partners (id={cascade_id})")
print(f"Components: {len(component_product_ids)} products with stock and vendor pricing")
print("Setup complete.")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# Record task start timestamp (after setup, before agent starts)
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open at Odoo home
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/odoo' &" 2>/dev/null
    sleep 5
fi

sleep 2
DISPLAY=:1 wmctrl -r Firefox -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Setup data: /tmp/smartdesk_setup.json"
echo "Desktop guide: /home/ga/Desktop/smartdesk_launch_guide.txt"
