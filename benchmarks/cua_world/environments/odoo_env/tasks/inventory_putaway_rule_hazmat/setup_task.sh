#!/bin/bash
# Setup script for inventory_putaway_rule_hazmat
# Sets up the product category, product, and vendor.
# Does NOT enable storage locations or create the specific location/rule (Agent's job).

echo "=== Setting up inventory_putaway_rule_hazmat ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Python script to populate initial data
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

# 1. Create Product Category: "Corrosives"
categ_ids = execute('product.category', 'search', [[['name', '=', 'Corrosives']]])
if categ_ids:
    categ_id = categ_ids[0]
    print(f"Using existing category: Corrosives (id={categ_id})")
else:
    categ_id = execute('product.category', 'create', [{
        'name': 'Corrosives',
        'parent_id': 1  # All
    }])
    print(f"Created category: Corrosives (id={categ_id})")

# 2. Create Product: "Sulfuric Acid 98%"
prod_ids = execute('product.product', 'search', [[['name', '=', 'Sulfuric Acid 98%']]])
if prod_ids:
    product_id = prod_ids[0]
    print(f"Using existing product: Sulfuric Acid 98% (id={product_id})")
else:
    product_id = execute('product.product', 'create', [{
        'name': 'Sulfuric Acid 98%',
        'categ_id': categ_id,
        'type': 'product',  # Storable product
        'purchase_ok': True,
        'sale_ok': True,
        'list_price': 45.00,
        'standard_price': 20.00,
    }])
    print(f"Created product: Sulfuric Acid 98% (id={product_id})")

# 3. Create Vendor: "Chemical Suppliers Inc"
partner_ids = execute('res.partner', 'search', [[['name', '=', 'Chemical Suppliers Inc']]])
if partner_ids:
    partner_id = partner_ids[0]
    print(f"Using existing vendor: Chemical Suppliers Inc (id={partner_id})")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': 'Chemical Suppliers Inc',
        'is_company': True,
        'supplier_rank': 1
    }])
    print(f"Created vendor: Chemical Suppliers Inc (id={partner_id})")

# Save setup info for verification
setup_info = {
    'categ_id': categ_id,
    'product_id': product_id,
    'partner_id': partner_id
}

with open('/tmp/setup_info.json', 'w') as f:
    json.dump(setup_info, f)

print("Setup complete.")
PYEOF

# Ensure Inventory app is installed (it usually is in odoo_env, but safe to check)
# We won't automate this via script to avoid complexity, assuming base env has it.
# Just ensuring window setup.

# Focus Firefox if running
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="