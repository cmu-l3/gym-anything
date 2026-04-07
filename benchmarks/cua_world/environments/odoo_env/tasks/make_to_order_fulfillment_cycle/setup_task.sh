#!/bin/bash
# Setup script for make_to_order_fulfillment_cycle task
# Installs Sales, Manufacturing, Purchase modules.
# Creates a manufactured product with BOM, components with stock levels
# (one component deliberately at zero), a customer, a vendor with pricelist.

echo "=== Setting up make_to_order_fulfillment_cycle ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Delete stale outputs before recording timestamp
rm -f /tmp/mto_fulfillment_setup.json /tmp/mto_fulfillment_result.json /tmp/task_result.json 2>/dev/null || true

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

# ─── Create Customer ─────────────────────────────────────────────────────────
CUSTOMER_NAME = 'TechWorld Distributors'

existing_cust = execute('res.partner', 'search_read',
    [[['name', '=', CUSTOMER_NAME], ['is_company', '=', True]]],
    {'fields': ['id'], 'limit': 1})

if existing_cust:
    customer_id = existing_cust[0]['id']
    print(f"Using existing customer: {CUSTOMER_NAME} (id={customer_id})")
else:
    customer_id = execute('res.partner', 'create', [{
        'name': CUSTOMER_NAME,
        'is_company': True,
        'customer_rank': 1,
        'street': '2500 Innovation Drive',
        'city': 'Austin',
        'zip': '78701',
        'country_id': 233,  # United States
        'email': 'orders@techworlddist.com',
        'phone': '(512) 555-0147',
    }])
    print(f"Created customer: {CUSTOMER_NAME} (id={customer_id})")

# ─── Create Vendor ────────────────────────────────────────────────────────────
VENDOR_NAME = 'ShenZhen MicroElectronics Co.'

existing_vendor = execute('res.partner', 'search_read',
    [[['name', '=', VENDOR_NAME], ['is_company', '=', True]]],
    {'fields': ['id'], 'limit': 1})

if existing_vendor:
    vendor_id = existing_vendor[0]['id']
    print(f"Using existing vendor: {VENDOR_NAME} (id={vendor_id})")
else:
    vendor_id = execute('res.partner', 'create', [{
        'name': VENDOR_NAME,
        'is_company': True,
        'supplier_rank': 1,
        'country_id': 44,  # China
    }])
    print(f"Created vendor: {VENDOR_NAME} (id={vendor_id})")

# ─── Define Products ─────────────────────────────────────────────────────────
COMPONENTS = [
    {"name": "4K CMOS Sensor Module",   "ref": "CMOS-4K",  "cost": 45.00,  "stock": 20},
    {"name": "Aluminum Housing Unit",   "ref": "ALU-HSG",  "cost": 18.00,  "stock": 50},
    {"name": "USB-C Controller Board",  "ref": "USBC-CTL", "cost": 28.50,  "stock": 0},
    {"name": "Pan-Tilt Motor Assembly", "ref": "PTM-ASSY", "cost": 35.00,  "stock": 15},
    {"name": "IR Emitter Array",        "ref": "IR-EMIT",  "cost": 12.00,  "stock": 30},
]

FINISHED_PRODUCT = {
    "name": "ProVision 4K Conference Camera",
    "ref": "PV4K-CAM",
    "sale_price": 425.00,
    "cost": 138.50,
}

# ─── Create Component Products ───────────────────────────────────────────────
component_product_ids = {}  # name -> product.product id
component_tmpl_ids = {}     # name -> product.template id

for comp in COMPONENTS:
    name = comp['name']

    existing = execute('product.template', 'search_read',
        [[['name', '=', name], ['active', '=', True]]],
        {'fields': ['id'], 'limit': 1})

    if existing:
        tmpl_id = existing[0]['id']
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': name,
            'default_code': comp['ref'],
            'type': 'product',
            'detailed_type': 'product',
            'sale_ok': False,
            'purchase_ok': True,
            'list_price': 0.0,
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
        # Check current stock
        quants = execute('stock.quant', 'search_read',
            [[['product_id', '=', prod_id], ['location_id', '=', stock_location_id]]],
            {'fields': ['quantity']})
        current_qty = sum(q['quantity'] for q in quants)

        if current_qty < comp['stock']:
            execute('stock.quant', 'create', [{
                'product_id': prod_id,
                'location_id': stock_location_id,
                'inventory_quantity': comp['stock'],
            }])
            # Also try direct quantity write as fallback
            try:
                execute('stock.quant', 'create', [{
                    'product_id': prod_id,
                    'location_id': stock_location_id,
                    'quantity': comp['stock'],
                }])
            except Exception:
                pass
            print(f"  Set stock for {name}: {comp['stock']} units")

# ─── Create Finished Product ─────────────────────────────────────────────────
fp_name = FINISHED_PRODUCT['name']

existing_fp = execute('product.template', 'search_read',
    [[['name', '=', fp_name], ['active', '=', True]]],
    {'fields': ['id'], 'limit': 1})

if existing_fp:
    fp_tmpl_id = existing_fp[0]['id']
    print(f"Using existing finished product: {fp_name} (tmpl_id={fp_tmpl_id})")
else:
    fp_tmpl_id = execute('product.template', 'create', [{
        'name': fp_name,
        'default_code': FINISHED_PRODUCT['ref'],
        'type': 'product',
        'detailed_type': 'product',
        'sale_ok': True,
        'purchase_ok': False,
        'list_price': FINISHED_PRODUCT['sale_price'],
        'standard_price': FINISHED_PRODUCT['cost'],
    }])
    print(f"Created finished product: {fp_name} (tmpl_id={fp_tmpl_id})")

# Get finished product variant ID
fp_variants = execute('product.product', 'search_read',
    [[['product_tmpl_id', '=', fp_tmpl_id], ['active', '=', True]]],
    {'fields': ['id'], 'limit': 1})
fp_product_id = fp_variants[0]['id'] if fp_variants else None

# ─── Create Bill of Materials ─────────────────────────────────────────────────
# Check if BOM already exists for this product
existing_bom = execute('mrp.bom', 'search_read',
    [[['product_tmpl_id', '=', fp_tmpl_id]]],
    {'fields': ['id'], 'limit': 1})

if existing_bom:
    bom_id = existing_bom[0]['id']
    print(f"Using existing BOM (id={bom_id})")
else:
    bom_id = execute('mrp.bom', 'create', [{
        'product_tmpl_id': fp_tmpl_id,
        'product_qty': 1.0,
        'type': 'normal',
    }])
    print(f"Created BOM (id={bom_id})")

    # Add BOM lines for each component
    for comp in COMPONENTS:
        name = comp['name']
        prod_id = component_product_ids[name]
        if prod_id:
            execute('mrp.bom.line', 'create', [{
                'bom_id': bom_id,
                'product_id': prod_id,
                'product_qty': 1.0,
            }])
            print(f"  Added BOM line: {name} x1")

# ─── Create Vendor Pricelist for USB-C Controller Board ───────────────────────
usbc_tmpl_id = component_tmpl_ids.get('USB-C Controller Board')
if usbc_tmpl_id and vendor_id:
    existing_supinfo = execute('product.supplierinfo', 'search_read',
        [[['partner_id', '=', vendor_id], ['product_tmpl_id', '=', usbc_tmpl_id]]],
        {'fields': ['id'], 'limit': 1})

    if not existing_supinfo:
        execute('product.supplierinfo', 'create', [{
            'partner_id': vendor_id,
            'product_tmpl_id': usbc_tmpl_id,
            'price': 28.50,
            'min_qty': 1,
        }])
        print(f"Created vendor pricelist: {VENDOR_NAME} -> USB-C Controller Board @ $28.50")
    else:
        print(f"Vendor pricelist already exists")

# ─── Save Setup Metadata ─────────────────────────────────────────────────────
setup_data = {
    'customer_id': customer_id,
    'customer_name': CUSTOMER_NAME,
    'vendor_id': vendor_id,
    'vendor_name': VENDOR_NAME,
    'finished_product_tmpl_id': fp_tmpl_id,
    'finished_product_id': fp_product_id,
    'finished_product_name': fp_name,
    'component_product_ids': component_product_ids,
    'component_tmpl_ids': component_tmpl_ids,
    'bom_id': bom_id,
    'stock_location_id': stock_location_id,
}

with open('/tmp/mto_fulfillment_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("\n=== Setup Summary ===")
print(f"Customer: {CUSTOMER_NAME} (id={customer_id})")
print(f"Vendor: {VENDOR_NAME} (id={vendor_id})")
print(f"Finished Product: {fp_name} (tmpl={fp_tmpl_id}, prod={fp_product_id})")
print(f"BOM: id={bom_id} with {len(COMPONENTS)} components")
for comp in COMPONENTS:
    pid = component_product_ids.get(comp['name'])
    print(f"  {comp['name']} (id={pid}): stock={comp['stock']}, cost=${comp['cost']:.2f}")
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

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Setup data: /tmp/mto_fulfillment_setup.json"
