#!/bin/bash
# Setup script for blanket_purchase_agreement_calloff task
# Creates the specific Vendor and Product required for the task.

echo "=== Setting up Blanket Purchase Agreement Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for screenshots
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Record start time
date +%s > /tmp/task_start_time.txt

# Create data via Python XML-RPC
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

# 1. Create/Find Vendor
vendor_name = "SoundWave Solutions Inc."
existing_vendor = execute('res.partner', 'search_read', 
    [[['name', '=', vendor_name], ['is_company', '=', True]]], 
    {'fields': ['id', 'name'], 'limit': 1})

if existing_vendor:
    vendor_id = existing_vendor[0]['id']
    print(f"Using existing vendor: {vendor_name} (id={vendor_id})")
else:
    vendor_id = execute('res.partner', 'create', [{
        'name': vendor_name,
        'is_company': True,
        'supplier_rank': 1,
        'email': 'sales@soundwave.example.com',
        'phone': '+1-206-555-0999'
    }])
    print(f"Created vendor: {vendor_name} (id={vendor_id})")

# 2. Create/Find Product
product_name = "Acoustic Isolation Panel"
existing_product = execute('product.template', 'search_read',
    [[['name', '=', product_name]]],
    {'fields': ['id', 'name'], 'limit': 1})

if existing_product:
    product_tmpl_id = existing_product[0]['id']
    print(f"Using existing product: {product_name} (id={product_tmpl_id})")
    # Reset standard price to ensure task is challenging
    execute('product.template', 'write', [[product_tmpl_id], {'standard_price': 55.00, 'list_price': 89.00}])
else:
    product_tmpl_id = execute('product.template', 'create', [{
        'name': product_name,
        'type': 'product', # Storable
        'purchase_ok': True,
        'sale_ok': True,
        'list_price': 89.00,
        'standard_price': 55.00, # Higher than agreement price
        'uom_id': 1, # Units
        'uom_po_id': 1
    }])
    print(f"Created product: {product_name} (id={product_tmpl_id})")

# Get product.product ID
product_variant = execute('product.product', 'search_read',
    [[['product_tmpl_id', '=', product_tmpl_id]]],
    {'fields': ['id'], 'limit': 1})
product_id = product_variant[0]['id']

# 3. Check Purchase Agreements Settings (Diagnostic only)
# We won't force enable it because that's part of the task, 
# but we want to know state for debugging if needed.
# (Settings are stored in res.config.settings but affect module installation/groups)

# Save setup metadata
setup_data = {
    'vendor_id': vendor_id,
    'vendor_name': vendor_name,
    'product_tmpl_id': product_tmpl_id,
    'product_id': product_id,
    'product_name': product_name,
    'standard_price': 55.00
}

with open('/tmp/blanket_order_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("Setup data saved to /tmp/blanket_order_setup.json")
PYEOF

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="